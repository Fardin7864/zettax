import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:primevest_mobile/core/account/account_models.dart';
import 'package:primevest_mobile/core/api/primevest_api_client.dart';
import 'package:primevest_mobile/core/auth/auth_models.dart';
import 'package:primevest_mobile/core/auth/token_store.dart';
import 'package:primevest_mobile/core/trading/trading_repository.dart';
import 'package:primevest_mobile/core/trading/pending_contract_store.dart';

void main() {
  test(
      'uncertain trade survives repository restart and retries the identical command',
      () async {
    final store = MemoryPendingContractStore();
    late RequestOptions original;
    final first = _repository((options) async {
      original = options;
      throw DioException(
          requestOptions: options, type: DioExceptionType.receiveTimeout);
    }, pendingStore: store);
    await expectLater(
        first.createTimedContract(
            mode: AccountMode.demo,
            instrumentId: 'btc-usd',
            direction: 'DOWN',
            investmentAmount: '1000.00',
            durationSeconds: 30,
            expectedProfitFeeRate: '0'),
        throwsException);
    expect(await store.read('test'), isNotNull);
    final recovered = _repository((options) async {
      expect(options.headers['Idempotency-Key'],
          original.headers['Idempotency-Key']);
      expect(options.data, original.data);
      return _jsonResponse({
        'data': {
          'id': 'contract-1',
          'instrumentId': 'btc-usd',
          'direction': 'DOWN',
          'investmentAmount': '1000.00',
          'entryPrice': '100',
          'entryTimestamp': '2026-09-12T00:00:00Z',
          'expiryTimestamp': '2026-09-12T00:00:30Z',
          'result': 'PENDING',
          'settlementModel': 'PROPORTIONAL_V2',
          'profitFeeRate': '0',
        },
        'meta': _meta
      });
    }, pendingStore: store);
    await expectLater(
        recovered.createTimedContract(
            mode: AccountMode.demo,
            instrumentId: 'btc-usd',
            direction: 'UP',
            investmentAmount: '1000.00',
            durationSeconds: 30,
            expectedProfitFeeRate: '0'),
        throwsException);
    expect((await recovered.retryPendingTimedContract()).id, 'contract-1');
    expect(await store.read('test'), isNull);
  });
  test('market order sends mode and quantity but never a client fill price',
      () async {
    late RequestOptions request;
    final repository = _repository((options) async {
      request = options;
      return _jsonResponse({
        'data': {
          'id': 'order-1',
          'instrumentId': 'btc-usd',
          'side': 'BUY',
          'quantity': '0.01000000',
          'averageFillPrice': '64000.00',
          'status': 'FILLED',
          'positionId': 'position-1',
        },
        'meta': _meta,
      });
    });

    final order = await repository.createMarketOrder(
      mode: AccountMode.demo,
      instrumentId: 'btc-usd',
      side: 'BUY',
      quantity: '0.01000000',
    );

    expect(request.path, '/orders');
    expect(request.headers['Authorization'], 'Bearer access-token');
    expect(request.headers['Idempotency-Key'], startsWith('order:'));
    expect(request.data, containsPair('accountMode', 'DEMO'));
    expect(request.data, containsPair('orderType', 'MARKET'));
    expect(request.data, isNot(contains('price')));
    expect(request.data, isNot(contains('fillPrice')));
    expect(order.positionId, 'position-1');
  });

  test('positions request remains explicitly scoped to REAL mode', () async {
    late RequestOptions request;
    final repository = _repository((options) async {
      request = options;
      return _jsonResponse({
        'data': {
          'items': [
            {
              'id': 'position-1',
              'instrumentId': 'eth-usd',
              'side': 'SELL',
              'quantity': '1.50000000',
              'averageEntry': '4500.00',
              'markPrice': '4400.00',
              'realizedPnl': '0.00',
              'unrealizedPnl': '150.00',
              'status': 'OPEN',
              'openedAt': '2026-09-09T12:00:00.000Z',
            },
          ],
        },
        'meta': _meta,
      });
    });

    final positions =
        await repository.positions(AccountMode.real, status: 'OPEN');

    expect(request.path, '/positions');
    expect(request.queryParameters, {
      'accountMode': 'REAL',
      'status': 'OPEN',
    });
    expect(positions.single.instrumentId, 'eth-usd');
    expect(positions.single.unrealizedPnl, '150.00');
  });

  test('position close is idempotent and carries no client price evidence',
      () async {
    late RequestOptions request;
    final repository = _repository((options) async {
      request = options;
      return _jsonResponse({
        'data': {
          'id': 'position-1',
          'instrumentId': 'btc-usd',
          'side': 'BUY',
          'quantity': '0.01000000',
          'averageEntry': '64000.00',
          'markPrice': '65000.00',
          'realizedPnl': '10.00',
          'unrealizedPnl': '0.00',
          'status': 'CLOSED',
          'openedAt': '2026-09-09T12:00:00.000Z',
        },
        'meta': _meta,
      });
    });

    await repository.closePosition('position-1');

    expect(request.path, '/positions/position-1/close');
    expect(request.headers['Idempotency-Key'], startsWith('close:'));
    expect(request.data, isNull);
  });
}

const _meta = {
  'requestId': '00000000-0000-4000-8000-000000000001',
  'timestamp': '2026-09-09T00:00:00.000Z',
};

TradingRepository _repository(
    Future<ResponseBody> Function(RequestOptions) callback,
    {PendingContractStore? pendingStore}) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.test/api/v1'));
  dio.httpClientAdapter = _CallbackAdapter(callback);
  return TradingRepository(
    PrimeVestApiClient(
      tokenStore: _MemoryTokenStore(),
      dio: dio,
      refreshDio: dio,
    ),
    pendingStore: pendingStore,
  );
}

ResponseBody _jsonResponse(Object body) => ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );

class _CallbackAdapter implements HttpClientAdapter {
  _CallbackAdapter(this.callback);
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

class _MemoryTokenStore implements TokenStore {
  @override
  Future<void> clearTokens() async {}

  @override
  Future<DeviceMetadata> deviceMetadata() async => const DeviceMetadata(
        deviceFingerprint: 'device-fingerprint-0001',
        deviceName: 'Test phone',
        devicePlatform: 'android',
      );

  @override
  Future<SessionTokens?> readTokens() async => const SessionTokens(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        accessTokenExpiresIn: 900,
      );

  @override
  Future<void> writeTokens(SessionTokens value) async {}
}
