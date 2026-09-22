import 'dart:async';

import 'package:primevest_mobile/core/api/api_environment.dart';
import 'package:primevest_mobile/core/auth/token_store.dart';
import 'package:primevest_mobile/market/market_data_api.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

class MarketRealtimeUpdate {
  const MarketRealtimeUpdate({
    required this.sequence,
    required this.instrumentId,
    required this.interval,
    required this.providerTimestamp,
    required this.receivedAt,
    required this.isFinal,
    required this.candle,
  });

  factory MarketRealtimeUpdate.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != 1 ||
        json['executionPrice'] != false ||
        json['executionEligible'] != false) {
      throw const FormatException('Unsafe realtime market event');
    }
    final rawCandle = json['candle'];
    if (rawCandle is! Map) {
      throw const FormatException('Missing realtime candle');
    }
    final sequence = int.tryParse(json['sequence']?.toString() ?? '');
    final instrumentId = json['instrumentId'];
    final interval = json['interval'];
    final providerTimestamp = DateTime.tryParse(
      json['providerTimestamp']?.toString() ?? '',
    );
    final receivedAt = DateTime.tryParse(json['receivedAt']?.toString() ?? '');
    if (sequence == null ||
        sequence < 1 ||
        instrumentId is! String ||
        interval is! String ||
        providerTimestamp == null ||
        receivedAt == null ||
        json['final'] is! bool) {
      throw const FormatException('Invalid realtime market event');
    }
    return MarketRealtimeUpdate(
      sequence: sequence,
      instrumentId: instrumentId,
      interval: interval,
      providerTimestamp: providerTimestamp.toUtc(),
      receivedAt: receivedAt.toUtc(),
      isFinal: json['final'] as bool,
      candle: MarketCandle.fromJson(Map<String, dynamic>.from(rawCandle)),
    );
  }

  final int sequence;
  final String instrumentId;
  final String interval;
  final DateTime providerTimestamp;
  final DateTime receivedAt;
  final bool isFinal;
  final MarketCandle candle;
}

class MarketRealtimeClient {
  const MarketRealtimeClient({required TokenStore tokenStore})
      : _tokenStore = tokenStore;

  final TokenStore _tokenStore;

  Future<MarketRealtimeSubscription?> subscribe({
    required String instrumentId,
    required String interval,
    required void Function(MarketRealtimeUpdate update) onCandle,
    required VoidCallback onSequenceGap,
    required void Function(bool connected) onConnectionChanged,
  }) async {
    final tokens = await _tokenStore.readTokens();
    final subscription = MarketRealtimeSubscription._(
      accessToken: tokens?.accessToken,
      instrumentId: instrumentId,
      interval: interval,
      onCandle: onCandle,
      onSequenceGap: onSequenceGap,
      onConnectionChanged: onConnectionChanged,
    );
    subscription.connect();
    return subscription;
  }
}

typedef VoidCallback = void Function();

class MarketRealtimeSubscription {
  MarketRealtimeSubscription._({
    required this.accessToken,
    required this.instrumentId,
    required this.interval,
    required this.onCandle,
    required this.onSequenceGap,
    required this.onConnectionChanged,
  });

  final String? accessToken;
  final String instrumentId;
  final String interval;
  final void Function(MarketRealtimeUpdate update) onCandle;
  final VoidCallback onSequenceGap;
  final void Function(bool connected) onConnectionChanged;
  io.Socket? _socket;
  int? _lastSequence;
  bool _accepted = false;
  bool _disposed = false;

  void connect() {
    if (_disposed || _socket != null) return;
    final api = Uri.parse(ApiEnvironment.baseUrlValue);
    final endpoint = api.replace(path: '/market', query: null, fragment: null);
    var options = io.OptionBuilder()
        .setTransports(['websocket'])
        .disableAutoConnect()
        .enableReconnection()
        .setReconnectionAttempts(20)
        .setReconnectionDelay(1000)
        .setReconnectionDelayMax(30000)
        .setTimeout(8000);
    final token = accessToken;
    if (token != null) options = options.setAuth({'token': token});
    final socket = io.io(endpoint.toString(), options.build());
    _socket = socket;
    socket.onConnect((_) {
      _accepted = false;
    });
    socket.on('market:ready', (_) {
      if (_disposed) return;
      socket.emitWithAck(
        'market:subscribe',
        {'instrumentId': instrumentId, 'interval': interval},
        ack: (dynamic response) {
          if (_disposed) return;
          final accepted = response is Map && response['ok'] == true;
          _accepted = accepted;
          onConnectionChanged(accepted);
          if (!accepted) dispose();
        },
      );
    });
    socket.onDisconnect((_) {
      _accepted = false;
      if (!_disposed) onConnectionChanged(false);
    });
    socket.on('market:error', (_) {
      _accepted = false;
      if (!_disposed) onConnectionChanged(false);
    });
    socket.on('market:candle', (dynamic payload) {
      if (_disposed || !_accepted || payload is! Map) return;
      try {
        final update = MarketRealtimeUpdate.fromJson(
          Map<String, dynamic>.from(payload),
        );
        if (update.instrumentId != instrumentId ||
            update.interval != interval) {
          return;
        }
        final previous = _lastSequence;
        if (previous != null && update.sequence != previous + 1) {
          onSequenceGap();
        }
        _lastSequence = update.sequence;
        onCandle(update);
      } on FormatException {
        onSequenceGap();
      }
    });
    socket.connect();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _accepted = false;
    onConnectionChanged(false);
    final socket = _socket;
    _socket = null;
    socket?.emit('market:unsubscribe');
    socket?.dispose();
  }
}
