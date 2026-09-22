import 'package:dio/dio.dart';
import 'package:primevest_mobile/core/api/api_contract.dart';
import 'package:primevest_mobile/core/api/api_environment.dart';
import 'package:primevest_mobile/demo/models.dart';

const primeVestApiBaseUrl = ApiEnvironment.baseUrlValue;

class MarketCandle {
  const MarketCandle({
    required this.openTime,
    required this.closeTime,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
  });

  factory MarketCandle.fromJson(Map<String, dynamic> json) {
    final candle = MarketCandle(
      openTime: _requiredDateTime(json, 'openTime'),
      closeTime: _requiredDateTime(json, 'closeTime'),
      open: _requiredNumber(json, 'open'),
      high: _requiredNumber(json, 'high'),
      low: _requiredNumber(json, 'low'),
      close: _requiredNumber(json, 'close'),
      volume: _optionalNumber(json, 'volume'),
    );
    if (candle.high < candle.low ||
        !candle.closeTime.isAfter(candle.openTime) ||
        candle.open < candle.low ||
        candle.open > candle.high ||
        candle.close < candle.low ||
        candle.close > candle.high) {
      throw const FormatException('Invalid market candle price range');
    }
    return candle;
  }

  final DateTime openTime;
  final DateTime closeTime;
  final double open;
  final double high;
  final double low;
  final double close;
  final double? volume;
}

class MarketCandleSeries {
  const MarketCandleSeries({
    required this.instrumentId,
    required this.symbol,
    required this.providerId,
    required this.provider,
    required this.sourceSymbol,
    required this.freshness,
    required this.requestedInterval,
    required this.effectiveInterval,
    required this.providerTimestamp,
    required this.executionPrice,
    required this.executionEligible,
    required this.isSyntheticOhlc,
    required this.receivedAt,
    required this.nextCursor,
    required this.candles,
    required this.delivery,
  });

  factory MarketCandleSeries.fromJson(Map<String, dynamic> json) {
    final executionPrice = json['executionPrice'];
    final executionEligible = json['executionEligible'];
    final isSyntheticOhlc = json['isSyntheticOhlc'];
    final rawCandles = json['candles'];
    if (executionPrice is! bool || executionPrice) {
      throw const FormatException(
        'Display-market response must not claim to be an execution price',
      );
    }
    if (executionEligible is! bool || executionEligible) {
      throw const FormatException(
        'Display-market response must not claim execution eligibility',
      );
    }
    if (isSyntheticOhlc is! bool) {
      throw const FormatException('Missing synthetic OHLC classification');
    }
    if (rawCandles is! List<dynamic> || rawCandles.isEmpty) {
      throw const FormatException('Market-data response has no candles');
    }

    final candles = rawCandles.map((item) {
      if (item is! Map) {
        throw const FormatException('Invalid market candle');
      }
      return MarketCandle.fromJson(Map<String, dynamic>.from(item));
    }).toList(growable: false);
    for (var index = 1; index < candles.length; index++) {
      if (candles[index].openTime.isBefore(candles[index - 1].openTime)) {
        throw const FormatException('Market candles are not chronological');
      }
    }

    return MarketCandleSeries(
      instrumentId: _requiredString(json, 'instrumentId'),
      symbol: _requiredString(json, 'symbol'),
      providerId: _requiredString(json, 'providerId'),
      provider: _requiredString(json, 'provider'),
      sourceSymbol: _requiredString(json, 'sourceSymbol'),
      freshness: _requiredString(json, 'freshness'),
      requestedInterval: _requiredString(json, 'requestedInterval'),
      effectiveInterval: _requiredString(json, 'effectiveInterval'),
      providerTimestamp: _requiredDateTime(json, 'providerTimestamp'),
      executionPrice: executionPrice,
      executionEligible: executionEligible,
      isSyntheticOhlc: isSyntheticOhlc,
      receivedAt: _requiredDateTime(json, 'receivedAt'),
      nextCursor: _optionalDateTime(json, 'nextCursor'),
      candles: candles,
      delivery: 'REST',
    );
  }

  final String instrumentId;
  final String symbol;
  final String providerId;
  final String provider;
  final String sourceSymbol;
  final String freshness;
  final String requestedInterval;
  final String effectiveInterval;
  final DateTime providerTimestamp;
  final bool executionPrice;
  final bool executionEligible;
  final bool isSyntheticOhlc;
  final DateTime receivedAt;
  final DateTime? nextCursor;
  final List<MarketCandle> candles;
  final String delivery;

  MarketCandleSeries mergeOlder(MarketCandleSeries older) {
    if (instrumentId != older.instrumentId ||
        requestedInterval != older.requestedInterval) {
      throw const FormatException('Historical page does not match series');
    }
    final byOpenTime = <DateTime, MarketCandle>{
      for (final candle in older.candles) candle.openTime: candle,
      for (final candle in candles) candle.openTime: candle,
    };
    final merged = byOpenTime.values.toList()
      ..sort((left, right) => left.openTime.compareTo(right.openTime));
    return MarketCandleSeries(
      instrumentId: instrumentId,
      symbol: symbol,
      providerId: providerId,
      provider: provider,
      sourceSymbol: sourceSymbol,
      freshness: freshness,
      requestedInterval: requestedInterval,
      effectiveInterval: effectiveInterval,
      providerTimestamp: providerTimestamp,
      executionPrice: false,
      executionEligible: false,
      isSyntheticOhlc: isSyntheticOhlc,
      receivedAt: receivedAt,
      nextCursor: older.nextCursor,
      candles: List.unmodifiable(merged),
      delivery: delivery,
    );
  }

  MarketCandleSeries mergeRealtime({
    required MarketCandle candle,
    required DateTime latestProviderTimestamp,
    required DateTime latestReceivedAt,
  }) {
    final byOpenTime = <DateTime, MarketCandle>{
      for (final existing in candles) existing.openTime: existing,
      candle.openTime: candle,
    };
    final merged = byOpenTime.values.toList()
      ..sort((left, right) => left.openTime.compareTo(right.openTime));
    return MarketCandleSeries(
      instrumentId: instrumentId,
      symbol: symbol,
      providerId: providerId,
      provider: provider,
      sourceSymbol: sourceSymbol,
      freshness: freshness,
      requestedInterval: requestedInterval,
      effectiveInterval: effectiveInterval,
      providerTimestamp: latestProviderTimestamp,
      executionPrice: false,
      executionEligible: false,
      isSyntheticOhlc: isSyntheticOhlc,
      receivedAt: latestReceivedAt,
      nextCursor: nextCursor,
      candles: List.unmodifiable(merged),
      delivery: 'WEBSOCKET',
    );
  }
}

String _requiredString(Map<String, dynamic> json, String key) {
  final raw = json[key];
  if (raw is! String || raw.trim().isEmpty) {
    throw FormatException('Missing $key');
  }
  return raw;
}

class MarketDataApi {
  MarketDataApi({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: primeVestApiBaseUrl,
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 10),
              headers: const {'Accept': 'application/json'},
            ));

  final Dio _dio;

  Future<List<MarketAsset>> fetchInstruments() async {
    final response =
        await _dio.get<Map<String, dynamic>>('/markets/instruments');
    final raw = response.data?['data'];
    if (raw is! List<dynamic>) {
      throw const FormatException('Invalid instrument catalogue');
    }
    return raw
        .map((item) =>
            MarketAsset.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
  }

  Future<MarketCandleSeries> fetchCandles(
    String instrumentId,
    String interval, {
    int limit = 90,
    DateTime? before,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/markets/instruments/$instrumentId/candles',
      queryParameters: {
        'interval': interval,
        'limit': limit,
        if (before != null) 'before': before.toUtc().toIso8601String(),
      },
    );
    final result = parseEnvelope(response.data);
    if (result.instrumentId != instrumentId ||
        result.requestedInterval != interval) {
      throw const FormatException(
          'Market-data response does not match request');
    }
    return result;
  }

  static MarketCandleSeries parseEnvelope(Map<String, dynamic>? envelope) {
    if (envelope == null) {
      throw const FormatException('Invalid market-data API envelope');
    }
    return ApiEnvelope<MarketCandleSeries>.fromJson(
      envelope,
      (payload) {
        if (payload is! Map) {
          throw const FormatException('Invalid market-data response');
        }
        return MarketCandleSeries.fromJson(
          Map<String, dynamic>.from(payload),
        );
      },
    ).data;
  }
}

DateTime _requiredDateTime(Map<String, dynamic> json, String key) {
  final raw = json[key];
  if (raw is! String) throw FormatException('Missing $key');
  final value = DateTime.tryParse(raw);
  if (value == null) throw FormatException('Invalid $key');
  return value.toUtc();
}

DateTime? _optionalDateTime(Map<String, dynamic> json, String key) {
  final raw = json[key];
  if (raw == null) return null;
  if (raw is! String) throw FormatException('Invalid $key');
  final value = DateTime.tryParse(raw);
  if (value == null) throw FormatException('Invalid $key');
  return value.toUtc();
}

double _requiredNumber(Map<String, dynamic> json, String key) {
  final raw = json[key];
  final value =
      raw is num ? raw.toDouble() : double.tryParse(raw?.toString() ?? '');
  if (value == null || !value.isFinite) {
    throw FormatException('Invalid $key');
  }
  return value;
}

double? _optionalNumber(Map<String, dynamic> json, String key) {
  if (json[key] == null) return null;
  return _requiredNumber(json, key);
}
