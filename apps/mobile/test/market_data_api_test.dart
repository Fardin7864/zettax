import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:primevest_mobile/market/market_data_api.dart';
import 'package:primevest_mobile/market/market_data_status.dart';
import 'package:primevest_mobile/market/market_realtime_client.dart';

void main() {
  Map<String, dynamic> envelope({
    bool executionPrice = false,
    String? nextCursor,
  }) =>
      {
        'data': {
          'instrumentId': 'btc-usd',
          'symbol': 'BTC/USD',
          'provider': 'Binance Public Spot',
          'providerId': 'binance-public-spot',
          'sourceSymbol': 'BTCUSDT',
          'freshness': 'DISPLAY_LIVE',
          'requestedInterval': '1h',
          'effectiveInterval': '1h',
          'providerTimestamp': '2026-09-08T05:59:59.999Z',
          'executionPrice': executionPrice,
          'executionEligible': false,
          'isSyntheticOhlc': false,
          'receivedAt': '2026-09-08T06:00:00.000Z',
          'nextCursor': nextCursor,
          'candles': [
            {
              'openTime': '2026-09-08T05:00:00.000Z',
              'closeTime': '2026-09-08T05:59:59.999Z',
              'open': '63000.25',
              'high': '64200.50',
              'low': '62900.00',
              'close': '64100.75',
              'volume': '12.5',
            },
          ],
        },
        'meta': {
          'requestId': 'request-id',
          'timestamp': '2026-09-08T06:00:00.000Z',
        },
      };

  test('parses the backend API envelope and normalized candle values', () {
    final result = MarketDataApi.parseEnvelope(envelope());

    expect(result.provider, 'Binance Public Spot');
    expect(result.executionPrice, isFalse);
    expect(result.executionEligible, isFalse);
    expect(result.isSyntheticOhlc, isFalse);
    expect(result.candles.single.open, 63000.25);
    expect(result.candles.single.close, 64100.75);
    expect(result.candles.single.volume, 12.5);
    expect(result.delivery, 'REST');
  });

  test('parses nextCursor and sends it back as exclusive before cursor',
      () async {
    final cursor = DateTime.utc(2026, 9, 8, 5);
    late RequestOptions request;
    final dio = Dio(BaseOptions(baseUrl: 'https://api.test/api/v1'));
    dio.httpClientAdapter = _CallbackAdapter((options) async {
      request = options;
      return ResponseBody.fromString(
        jsonEncode(envelope(nextCursor: cursor.toIso8601String())),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    });

    final result = await MarketDataApi(dio: dio).fetchCandles(
      'btc-usd',
      '1h',
      limit: 40,
      before: cursor,
    );

    expect(result.nextCursor, cursor);
    expect(request.queryParameters, {
      'interval': '1h',
      'limit': 40,
      'before': '2026-09-08T05:00:00.000Z',
    });
  });

  test('merges overlapping historical pages chronologically', () {
    final latestEnvelope = envelope(nextCursor: '2026-09-08T05:00:00.000Z');
    final olderEnvelope = envelope(nextCursor: null);
    final olderData = olderEnvelope['data'] as Map<String, dynamic>;
    olderData['candles'] = [
      {
        'openTime': '2026-09-08T04:00:00.000Z',
        'closeTime': '2026-09-08T04:59:59.999Z',
        'open': '62000',
        'high': '63100',
        'low': '61900',
        'close': '63000',
        'volume': '10',
      },
      ...(olderData['candles'] as List<dynamic>),
    ];

    final merged = MarketDataApi.parseEnvelope(latestEnvelope)
        .mergeOlder(MarketDataApi.parseEnvelope(olderEnvelope));

    expect(merged.candles, hasLength(2));
    expect(merged.candles.first.openTime, DateTime.utc(2026, 9, 8, 4));
    expect(merged.nextCursor, isNull);
  });

  test('rejects display data that claims to be an execution price', () {
    expect(
      () => MarketDataApi.parseEnvelope(envelope(executionPrice: true)),
      throwsFormatException,
    );
  });

  test('rejects display data that claims execution eligibility', () {
    final response = envelope();
    (response['data'] as Map<String, dynamic>)['executionEligible'] = true;

    expect(
      () => MarketDataApi.parseEnvelope(response),
      throwsFormatException,
    );
  });

  test('renders explicit provider freshness and deterministic age labels', () {
    expect(marketFreshnessLabel('REFERENCE_DAILY'), 'daily reference');
    expect(marketFreshnessLabel('DISPLAY_LIVE'), 'live display feed');
    expect(
      marketDataAge(
        DateTime.utc(2026, 9, 8, 5, 58),
        now: DateTime.utc(2026, 9, 8, 6),
      ),
      '2m ago',
    );
  });

  test('normalizes a safe realtime candle and merges the current interval', () {
    final update = MarketRealtimeUpdate.fromJson({
      'schemaVersion': 1,
      'sequence': '9',
      'instrumentId': 'btc-usd',
      'interval': '1h',
      'providerTimestamp': '2026-09-08T06:30:00.000Z',
      'receivedAt': '2026-09-08T06:30:00.100Z',
      'executionPrice': false,
      'executionEligible': false,
      'final': false,
      'candle': {
        'openTime': '2026-09-08T06:00:00.000Z',
        'closeTime': '2026-09-08T06:59:59.999Z',
        'open': '64100',
        'high': '64500',
        'low': '64000',
        'close': '64400',
        'volume': '7.5',
      },
    });
    final original = MarketDataApi.parseEnvelope(envelope());
    final merged = original.mergeRealtime(
      candle: update.candle,
      latestProviderTimestamp: update.providerTimestamp,
      latestReceivedAt: update.receivedAt,
    );

    expect(update.sequence, 9);
    expect(merged.candles, hasLength(2));
    expect(merged.candles.last.close, 64400);
    expect(merged.executionPrice, isFalse);
    expect(merged.executionEligible, isFalse);
    expect(merged.delivery, 'WEBSOCKET');
  });

  test('rejects realtime events claiming execution authority', () {
    expect(
      () => MarketRealtimeUpdate.fromJson({
        'schemaVersion': 1,
        'executionPrice': true,
        'executionEligible': false,
      }),
      throwsFormatException,
    );
  });
}

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
