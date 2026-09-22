import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:primevest_mobile/core/api/api_environment.dart';
import 'package:primevest_mobile/core/auth/token_store.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

class AccountRealtimeEvent {
  const AccountRealtimeEvent({
    required this.sequence,
    required this.type,
    required this.payload,
  });

  factory AccountRealtimeEvent.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != 1) {
      throw const FormatException('Unsupported account event schema');
    }
    final sequence = int.tryParse(json['sequence']?.toString() ?? '');
    final type = json['type'];
    final payload = json['payload'];
    if (sequence == null ||
        sequence < 1 ||
        type is! String ||
        payload is! Map) {
      throw const FormatException('Invalid account event');
    }
    return AccountRealtimeEvent(
      sequence: sequence,
      type: type,
      payload: Map<String, dynamic>.from(payload),
    );
  }

  final int sequence;
  final String type;
  final Map<String, dynamic> payload;
}

abstract interface class AccountEventCursorStore {
  Future<int?> read();
  Future<void> write(int sequence);
}

class SecureAccountEventCursorStore implements AccountEventCursorStore {
  SecureAccountEventCursorStore(
      {FlutterSecureStorage? storage, String userId = 'guest'})
      : _storage = storage ?? const FlutterSecureStorage(),
        _key = 'account.last_event_sequence.$userId';

  final String _key;
  final FlutterSecureStorage _storage;

  @override
  Future<int?> read() async =>
      int.tryParse(await _storage.read(key: _key) ?? '');

  @override
  Future<void> write(int sequence) =>
      _storage.write(key: _key, value: sequence.toString());
}

class AccountRealtimeClient {
  const AccountRealtimeClient({
    required TokenStore tokenStore,
    required AccountEventCursorStore cursorStore,
  })  : _tokenStore = tokenStore,
        _cursorStore = cursorStore;

  final TokenStore _tokenStore;
  final AccountEventCursorStore _cursorStore;

  Future<AccountRealtimeSubscription?> subscribe({
    required VoidCallback onAccountStateChanged,
    required void Function(AccountRealtimeEvent event) onEvent,
    required void Function(bool connected) onConnectionChanged,
    Future<String?> Function()? renewAccessToken,
  }) async {
    final tokens = await _tokenStore.readTokens();
    if (tokens == null) return null;
    final subscription = AccountRealtimeSubscription._(
      accessToken: tokens.accessToken,
      cursorStore: _cursorStore,
      initialSequence: await _cursorStore.read(),
      onAccountStateChanged: onAccountStateChanged,
      onEvent: onEvent,
      onConnectionChanged: onConnectionChanged,
      renewAccessToken: renewAccessToken,
    );
    subscription.connect();
    return subscription;
  }
}

typedef VoidCallback = void Function();

class AccountRealtimeSubscription {
  AccountRealtimeSubscription._({
    required this.accessToken,
    required this.cursorStore,
    required this.initialSequence,
    required this.onAccountStateChanged,
    required this.onEvent,
    required this.onConnectionChanged,
    this.renewAccessToken,
  });

  String accessToken;
  final Future<String?> Function()? renewAccessToken;
  final AccountEventCursorStore cursorStore;
  final int? initialSequence;
  final VoidCallback onAccountStateChanged;
  final void Function(AccountRealtimeEvent event) onEvent;
  final void Function(bool connected) onConnectionChanged;
  io.Socket? _socket;
  int? _lastSequence;
  bool _disposed = false;
  bool _recovering = false;
  bool _refreshingAuth = false;

  void connect() {
    if (_disposed || _socket != null) return;
    _lastSequence = initialSequence;
    final api = Uri.parse(ApiEnvironment.baseUrlValue);
    final endpoint = api.replace(path: '/account', query: null, fragment: null);
    final auth = <String, dynamic>{'token': accessToken};
    if (initialSequence != null) {
      auth['afterSequence'] = initialSequence.toString();
    }
    final socket = io.io(
      endpoint.toString(),
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .enableReconnection()
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(30000)
          .setTimeout(8000)
          .setAuth(auth)
          .build()
        ..addAll({'forceNew': true, 'multiplex': false}),
    );
    _socket = socket;
    socket.on('account:snapshot', (dynamic payload) async {
      if (_disposed || payload is! Map) return;
      final version =
          int.tryParse(payload['snapshotVersion']?.toString() ?? '');
      if (version == null || version < 0) return;
      await _advance(version, notify: true);
    });
    socket.on('account:recovery', (dynamic payload) {
      if (payload is Map) _applyRecovery(Map<String, dynamic>.from(payload));
    });
    socket.on('account:event', (dynamic payload) {
      if (payload is Map) _applyEvent(Map<String, dynamic>.from(payload));
    });
    socket.on('account:ready', (_) {
      if (!_disposed) onConnectionChanged(true);
    });
    socket.onDisconnect((_) {
      if (!_disposed) {
        socket.auth = {
          'token': accessToken,
          if (_lastSequence != null) 'afterSequence': '$_lastSequence'
        };
        onConnectionChanged(false);
      }
    });
    socket.on('account:error', (dynamic payload) {
      if (_disposed || payload is! Map) return;
      final code = payload['code'];
      if (code == 'ACCOUNT_SEQUENCE_INVALID') return;
      onConnectionChanged(false);
      if (code == 'AUTH_SESSION_EXPIRED' || code == 'AUTH_REQUIRED') {
        unawaited(_renewAuthentication());
      }
    });
    socket.connect();
  }

  Future<void> _renewAuthentication() async {
    if (_disposed || _refreshingAuth || renewAccessToken == null) return;
    _refreshingAuth = true;
    try {
      final token = await renewAccessToken!();
      if (_disposed || token == null) return;
      accessToken = token;
      _socket?.auth = {
        'token': token,
        if (_lastSequence != null) 'afterSequence': '$_lastSequence'
      };
      _socket?.connect();
    } catch (_) {
      if (!_disposed) onConnectionChanged(false);
    } finally {
      _refreshingAuth = false;
    }
  }

  Future<void> _applyEvent(Map<String, dynamic> payload) async {
    try {
      final event = AccountRealtimeEvent.fromJson(payload);
      final previous = _lastSequence ?? 0;
      if (event.sequence <= previous) return;
      if (event.sequence != previous + 1) {
        _requestRecovery(previous);
        return;
      }
      await _advance(event.sequence, notify: true);
      if (!_disposed) onEvent(event);
    } on FormatException {
      _requestRecovery(_lastSequence ?? 0);
    }
  }

  Future<void> _applyRecovery(Map<String, dynamic> payload) async {
    if (_disposed) return;
    final rawEvents = payload['events'];
    if (rawEvents is! List) return _requestRecovery(_lastSequence ?? 0);
    var expected = (_lastSequence ?? 0) + 1;
    var changed = false;
    try {
      for (final raw in rawEvents) {
        if (raw is! Map) throw const FormatException('Invalid recovery event');
        final event = AccountRealtimeEvent.fromJson(
          Map<String, dynamic>.from(raw),
        );
        if (event.sequence < expected) continue;
        if (event.sequence != expected) {
          throw const FormatException('Account event sequence gap');
        }
        await _advance(event.sequence);
        if (!_disposed) onEvent(event);
        expected += 1;
        changed = true;
      }
      if (changed) onAccountStateChanged();
      if (payload['complete'] != true) _requestRecovery(_lastSequence ?? 0);
    } on FormatException {
      _requestRecovery(_lastSequence ?? 0);
    }
  }

  void _requestRecovery(int after) {
    final socket = _socket;
    if (_disposed || _recovering || socket == null) return;
    _recovering = true;
    socket.emitWithAck(
      'account:recover',
      {'afterSequence': after.toString()},
      ack: (dynamic response) async {
        _recovering = false;
        if (response is Map && response['ok'] == true) {
          await _applyRecovery(Map<String, dynamic>.from(response));
        }
      },
    );
  }

  Future<void> _advance(int sequence, {bool notify = false}) async {
    if (_disposed || sequence < (_lastSequence ?? 0)) return;
    _lastSequence = sequence;
    await cursorStore.write(sequence);
    if (notify && !_disposed) onAccountStateChanged();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    onConnectionChanged(false);
    final socket = _socket;
    _socket = null;
    socket?.dispose();
  }
}
