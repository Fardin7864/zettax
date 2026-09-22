import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:primevest_mobile/core/account/account_models.dart';
import 'package:primevest_mobile/core/account/account_repository.dart';
import 'package:primevest_mobile/core/api/primevest_api_client.dart';
import 'package:primevest_mobile/core/auth/auth_models.dart';
import 'package:primevest_mobile/core/auth/auth_repository.dart';
import 'package:primevest_mobile/core/auth/token_store.dart';

void main() {
  test('login follows auth contract and persists returned tokens', () async {
    final store = MemoryTokenStore();
    late RequestOptions request;
    final adapter = CallbackAdapter((options) async {
      request = options;
      return jsonResponse(_authEnvelope());
    });
    final dio = testDio(adapter);
    final repository = AuthRepository(
      client: PrimeVestApiClient(
        tokenStore: store,
        dio: dio,
        refreshDio: dio,
      ),
      tokenStore: store,
    );

    final result = await repository.login(
      const LoginCommand(
        identifier: 'investor@example.com',
        password: 'Strong!Password1',
      ),
    );

    expect(request.path, '/auth/login');
    expect(request.data,
        containsPair('deviceFingerprint', 'device-fingerprint-0001'));
    expect(result.user.email, 'investor@example.com');
    expect((await store.readTokens())?.refreshToken, 'refresh-2');
  });

  test('parallel refresh callers share one rotating-token request', () async {
    final store = MemoryTokenStore(
      tokens: const SessionTokens(
        accessToken: 'access-1',
        refreshToken: 'refresh-1',
        accessTokenExpiresIn: 900,
      ),
    );
    var calls = 0;
    final adapter = CallbackAdapter((options) async {
      calls++;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return jsonResponse(_authEnvelope());
    });
    final dio = testDio(adapter);
    final client = PrimeVestApiClient(
      tokenStore: store,
      dio: dio,
      refreshDio: dio,
    );

    final results = await Future.wait([
      client.refreshSession(),
      client.refreshSession(),
      client.refreshSession(),
    ]);

    expect(calls, 1);
    expect(results.map((item) => item.tokens.accessToken),
        everyElement('access-2'));
    expect((await store.readTokens())?.refreshToken, 'refresh-2');
  });

  test('accounts repository parses DEMO and REAL as separated summaries',
      () async {
    final adapter = CallbackAdapter((options) async => jsonResponse({
          'data': [
            _account('demo-account', 'DEMO', '100000.00'),
            _account('real-account', 'REAL', '0.00'),
          ],
          'meta': _meta,
        }));
    final store = MemoryTokenStore(
      tokens: const SessionTokens(
        accessToken: 'access-1',
        refreshToken: 'refresh-1',
        accessTokenExpiresIn: 900,
      ),
    );
    final dio = testDio(adapter);
    final repository = AccountRepository(
      PrimeVestApiClient(tokenStore: store, dio: dio, refreshDio: dio),
    );

    final accounts = await repository.accounts();

    expect(accounts.map((item) => item.mode),
        [AccountMode.demo, AccountMode.real]);
    expect(accounts.first.wallets.single.available, '100000.00');
    expect(accounts.last.wallets.single.available, '0.00');
  });
}

const _meta = {
  'requestId': '00000000-0000-4000-8000-000000000001',
  'timestamp': '2026-09-09T00:00:00.000Z',
};

Map<String, dynamic> _authEnvelope() => {
      'data': {
        'accessToken': 'access-2',
        'refreshToken': 'refresh-2',
        'tokenType': 'Bearer',
        'accessTokenExpiresIn': 900,
        'user': {
          'id': 'user-1',
          'email': 'investor@example.com',
          'phone': '+8801712345678',
        },
      },
      'meta': _meta,
    };

Map<String, dynamic> _account(String id, String mode, String available) => {
      'id': id,
      'mode': mode,
      'status': 'ACTIVE',
      'wallets': [
        {
          'currencyCode': 'BDT',
          'available': available,
          'locked': '0.00',
          'equity': available,
        },
      ],
      'openPositionCount': 0,
      'createdAt': '2026-09-09T00:00:00.000Z',
    };

Dio testDio(HttpClientAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.test/api/v1'));
  dio.httpClientAdapter = adapter;
  return dio;
}

ResponseBody jsonResponse(Object body, {int statusCode = 200}) =>
    ResponseBody.fromString(
      jsonEncode(body),
      statusCode,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );

class CallbackAdapter implements HttpClientAdapter {
  CallbackAdapter(this.callback);
  final Future<ResponseBody> Function(RequestOptions options) callback;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) =>
      callback(options);

  @override
  void close({bool force = false}) {}
}

class MemoryTokenStore implements TokenStore {
  MemoryTokenStore({this.tokens});
  SessionTokens? tokens;

  @override
  Future<void> clearTokens() async => tokens = null;

  @override
  Future<DeviceMetadata> deviceMetadata() async => const DeviceMetadata(
        deviceFingerprint: 'device-fingerprint-0001',
        deviceName: 'Test phone',
        devicePlatform: 'android',
      );

  @override
  Future<SessionTokens?> readTokens() async => tokens;

  @override
  Future<void> writeTokens(SessionTokens value) async => tokens = value;
}
