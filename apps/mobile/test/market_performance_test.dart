import 'package:flutter_test/flutter_test.dart';
import 'package:primevest_mobile/features/shared/market_performance.dart';
import 'package:primevest_mobile/market/market_data_api.dart';

void main() {
  final asOf = DateTime.utc(2026, 9, 23, 14);
  MarketCandle candle(int daysAgo, double open) {
    final day = DateTime.utc(2026, 9, 23).subtract(Duration(days: daysAgo));
    return MarketCandle(
      openTime: day,
      closeTime: day.add(const Duration(days: 1)),
      open: open,
      high: open + 10,
      low: open - 10,
      close: open + 1,
      volume: 12,
    );
  }

  test('period returns use the exact observed UTC day open', () {
    final history = [candle(365, 50), candle(7, 80), candle(0, 100)];
    expect(marketPeriodReturn(history, 110, asOf, 0), closeTo(10, 0.00001));
    expect(marketPeriodReturn(history, 110, asOf, 7), closeTo(37.5, 0.00001));
    expect(marketPeriodReturn(history, 110, asOf, 365), closeTo(120, 0.00001));
  });

  test('missing history is unavailable instead of an invented return', () {
    final history = [candle(8, 80), candle(0, 100)];
    expect(marketPeriodReturn(history, 110, asOf, 7), isNull);
    expect(marketPeriodReturn(history, 110, asOf, 30), isNull);
    expect(marketPeriodReturn(history, double.nan, asOf, 0), isNull);
  });

  MarketCandleSeries minuteSeries({bool gap = false, String interval = '1m'}) {
    final candles = List.generate(15, (index) {
      final offset = gap && index >= 8 ? 1 : 0;
      final openTime = DateTime.utc(2026, 9, 23, 13, index + offset);
      final open = 100 + index.toDouble();
      return MarketCandle(
          openTime: openTime,
          closeTime: openTime.add(const Duration(minutes: 1)),
          open: open,
          high: open + 2,
          low: open - 1,
          close: open + 1,
          volume: 1);
    });
    return MarketCandleSeries(
        instrumentId: 'btc-usd',
        symbol: 'BTC/USD',
        providerId: 'test',
        provider: 'Observed',
        sourceSymbol: 'BTCUSDT',
        freshness: 'LIVE',
        requestedInterval: '1m',
        effectiveInterval: interval,
        providerTimestamp: candles.last.closeTime,
        executionPrice: false,
        executionEligible: false,
        isSyntheticOhlc: false,
        receivedAt: candles.last.closeTime,
        nextCursor: null,
        candles: candles,
        delivery: 'REST');
  }

  test('1m and 15m changes use observed minute-bar opens', () {
    final series = minuteSeries();
    expect(marketMinuteMove(series, 1)?.amount, 1);
    expect(marketMinuteMove(series, 15)?.amount, 15);
    expect(marketMinuteMove(series, 15)?.percent, 15);
  });

  test('minute changes are unavailable for missing bars or wider intervals',
      () {
    expect(marketMinuteMove(minuteSeries(gap: true), 15), isNull);
    expect(marketMinuteMove(minuteSeries(interval: '15m'), 1), isNull);
    expect(marketMinuteMove(minuteSeries(), 16), isNull);
  });
}
