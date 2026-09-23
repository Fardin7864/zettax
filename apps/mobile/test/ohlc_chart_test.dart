import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:primevest_mobile/features/shared/ohlc_chart.dart';

void main() {
  test('zoom widens candle bodies without introducing inter-candle gaps', () {
    final normal = chartBodyWidth(360, 42);
    final zoomed = chartBodyWidth(360, 21);
    expect(zoomed, greaterThan(normal * 1.8));
    expect(normal / ((360 - 64) / 44), greaterThan(.97));
    expect(zoomed / ((360 - 64) / 23), greaterThan(.97));
  });

  test('moving averages use only observed closing prices and volumes', () {
    final observed = List.generate(
        100,
        (index) => ChartCandle(
              time: DateTime.utc(2026, 9, 23).add(Duration(minutes: index)),
              open: index.toDouble(),
              high: index + 1.0,
              low: index.toDouble(),
              close: index + 1.0,
              volume: index + 1.0,
            ));
    expect(candleAverage(observed, 99, 7), 97);
    expect(candleAverage(observed, 99, 25), 88);
    expect(candleAverage(observed, 99, 99), 51);
    expect(candleAverage(observed, 99, 10, volume: true), 95.5);
    expect(candleAverage(observed, 97, 99), isNull);
  });
  final candles = List.generate(60, (index) {
    final open = 100 + index.toDouble();
    return ChartCandle(
      time: DateTime.utc(2026, 9, 1).add(Duration(hours: index)),
      open: open,
      high: open + 2,
      low: open - 1,
      close: open + 1,
    );
  });

  Widget subject({
    ValueChanged<ChartCandle?>? onSelectionChanged,
    void Function(int, int)? onViewportChanged,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            child: OhlcChart(
              candles: candles,
              precision: 2,
              onSelectionChanged: onSelectionChanged,
              onViewportChanged: onViewportChanged,
            ),
          ),
        ),
      );

  testWidgets('tap selects the candle under the crosshair', (tester) async {
    ChartCandle? selected;
    await tester.pumpWidget(subject(onSelectionChanged: (value) {
      selected = value;
    }));

    await tester.tapAt(tester.getCenter(find.byType(OhlcChart)));
    await tester.pump();

    // Initial viewport contains candles 18...59. The reserved future-trade
    // space means the visual center maps to a candle after the data midpoint.
    expect(selected, isNotNull);
    expect(selected!.open, greaterThan(139));
    final chartSemantics = tester.getSemantics(find.byType(OhlcChart));
    expect(
      chartSemantics.value,
      contains('Open ${selected!.open.toStringAsFixed(2)}'),
    );
    expect(
      chartSemantics.value,
      contains('close ${selected!.close.toStringAsFixed(2)}'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('pinch zoom publishes a smaller visible range', (tester) async {
    var visible = 42;
    await tester.pumpWidget(subject(onViewportChanged: (start, end) {
      visible = end - start;
    }));
    final center = tester.getCenter(find.byType(OhlcChart));
    final first =
        await tester.startGesture(center - const Offset(50, 0), pointer: 1);
    final second =
        await tester.startGesture(center + const Offset(50, 0), pointer: 2);

    await first.moveTo(center - const Offset(100, 0));
    await second.moveTo(center + const Offset(100, 0));
    await tester.pump();
    await first.up();
    await second.up();

    expect(visible, lessThan(42));
    expect(visible, greaterThanOrEqualTo(8));
  });

  testWidgets('announces chart interaction instructions', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(subject());

    expect(
      find.bySemanticsLabel(RegExp('Interactive candlestick chart')),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('panning to the oldest visible candle requests more history',
      (tester) async {
    var loadRequests = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 420,
          child: OhlcChart(
            candles: candles,
            precision: 2,
            onLoadOlder: () => loadRequests++,
          ),
        ),
      ),
    ));

    await tester.drag(find.byType(OhlcChart), const Offset(500, 0));
    await tester.pump();

    expect(loadRequests, greaterThan(0));
  });
}
