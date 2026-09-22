import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:primevest_mobile/features/shared/live_trade_chart.dart';
import 'package:primevest_mobile/features/shared/ohlc_chart.dart';
import 'package:primevest_mobile/market/market_data_api.dart';

void main() {
  testWidgets(
      'live candlesticks handle flat prices, multiple expiries and new observations',
      (tester) async {
    final now = DateTime.now();
    MarketCandleSeries series(double price, DateTime receipt) =>
        MarketCandleSeries(
            instrumentId: 'btc-usd',
            symbol: 'BTC/USD',
            providerId: 'test',
            provider: 'test',
            sourceSymbol: 'BTCUSDT',
            freshness: 'DISPLAY_LIVE',
            requestedInterval: '1m',
            effectiveInterval: '1m',
            providerTimestamp: receipt,
            executionPrice: false,
            executionEligible: false,
            isSyntheticOhlc: false,
            receivedAt: receipt,
            nextCursor: null,
            delivery: 'WEBSOCKET',
            candles: [
              for (var i = 5; i >= 0; i--)
                MarketCandle(
                    openTime: now.subtract(Duration(minutes: i + 1)),
                    closeTime: now.subtract(Duration(minutes: i)),
                    open: price,
                    high: price,
                    low: price,
                    close: price,
                    volume: null),
            ]);
    Widget app(MarketCandleSeries data) => MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 320,
                height: 420,
                child: Column(children: [
                  Expanded(
                      child:
                          LiveTradeChart(series: data, precision: 2, markers: [
                    for (var i = 0; i < 3; i++)
                      ChartTradeMarker(
                          id: '$i',
                          openedAt: now,
                          endsAt: now.add(Duration(seconds: 30 + 120 * i)),
                          price: 100,
                          label: 'BUY ৳1000'),
                  ])),
                ]))));
    await tester.pumpWidget(app(series(100, now)));
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.takeException(), isNull);
    await tester
        .pumpWidget(app(series(101, now.add(const Duration(seconds: 1)))));
    await tester.pump(const Duration(milliseconds: 350));
    expect(tester.takeException(), isNull);
    expect(find.byType(LiveTradeChart), findsOneWidget);
    expect(find.byType(OhlcChart), findsOneWidget);
    final candleCanvas = find.descendant(
      of: find.byType(OhlcChart),
      matching: find.byType(CustomPaint),
    );
    expect(tester.getSize(candleCanvas).width, 320);
    expect(
      find.bySemanticsLabel(RegExp('Interactive candlestick chart')),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });
}
