import 'package:primevest_mobile/app/terminal_design.dart';
import 'package:flutter/material.dart';
import 'dart:math';
import 'package:primevest_mobile/features/shared/ohlc_chart.dart';
import 'package:primevest_mobile/market/market_data_api.dart';

/// Live OHLC presentation backed by the existing market and trade data.
class LiveTradeChart extends StatefulWidget {
  const LiveTradeChart({
    super.key,
    required this.series,
    required this.precision,
    this.markers = const [],
    this.showTools = false,
  });

  final MarketCandleSeries series;
  final int precision;
  final List<ChartTradeMarker> markers;
  final bool showTools;
  @override
  State<LiveTradeChart> createState() => _LiveTradeChartState();
}

class _LiveTradeChartState extends State<LiveTradeChart> {
  bool lineMode = false;
  MarketCandleSeries get series => widget.series;
  int get precision => widget.precision;
  List<ChartTradeMarker> get markers => widget.markers;

  @override
  Widget build(BuildContext context) {
    final candles = series.candles;
    final high = candles.map((candle) => candle.high).reduce(max);
    final low = candles.map((candle) => candle.low).reduce(min);
    final change = candles.first.open == 0
        ? null
        : (candles.last.close / candles.first.open - 1) * 100;
    final volume = candles.every((candle) => candle.volume != null)
        ? candles.fold<double>(0, (sum, candle) => sum + candle.volume!)
        : null;
    final chartCandles = candles.map(ChartCandle.fromMarket).toList();
    final stats = <String>[
      'Loaded ${candles.length} bars',
      'High ${high.toStringAsFixed(precision)}',
      'Low ${low.toStringAsFixed(precision)}',
      if (change != null)
        'Change ${change >= 0 ? '+' : ''}${change.toStringAsFixed(2)}%',
      if (volume != null)
        'Vol ${volume.toStringAsFixed(2)} ${series.sourceSymbol.endsWith('USDT') ? series.sourceSymbol.replaceAll('USDT', '') : ''}',
      series.provider,
    ];
    return RepaintBoundary(
      child: Column(children: [
        if (widget.showTools)
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(children: [
                Expanded(
                    child: TextButton.icon(
                        onPressed: () =>
                            terminalSheet(context, 'Technical indicators', [
                              const Text(
                                  'Moving averages use observed closing prices. A value is unavailable until enough bars are loaded.',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: TerminalDesign.muted)),
                              for (final period in [7, 25, 99])
                                ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text('MA($period)'),
                                    trailing: Text(
                                        candleAverage(
                                                    chartCandles,
                                                    chartCandles.length - 1,
                                                    period)
                                                ?.toStringAsFixed(precision) ??
                                            '—',
                                        style: const TextStyle(
                                            color: TerminalDesign.gold))),
                              const Text(
                                  'Volume and its averages appear when the data provider supplies volume.',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: TerminalDesign.muted)),
                            ]),
                        icon: const Icon(Icons.tune, size: 16),
                        label: const Text('Indicators',
                            style: TextStyle(fontSize: 11)))),
                IconButton(
                    tooltip: 'Candlestick chart',
                    isSelected: !lineMode,
                    onPressed: () => setState(() => lineMode = false),
                    icon:
                        const Icon(Icons.candlestick_chart_outlined, size: 19)),
                IconButton(
                    tooltip: 'Line chart',
                    isSelected: lineMode,
                    onPressed: () => setState(() => lineMode = true),
                    icon: const Icon(Icons.show_chart, size: 19)),
              ])),
        SizedBox(
          height:
              20 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0),
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final (period, color) in [
                (7, const Color(0xFFF6C342)),
                (25, const Color(0xFFEF5DA8)),
                (99, const Color(0xFFA78BFA)),
              ])
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 3),
                  child: Text(
                    'MA($period): ${candleAverage(chartCandles, chartCandles.length - 1, period)?.toStringAsFixed(precision) ?? '—'}',
                    style: TextStyle(color: color, fontSize: 10),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
            child: OhlcChart(
          candles: chartCandles,
          precision: precision,
          tradeMarkers: markers,
          lineMode: lineMode,
        )),
        SizedBox(
          height:
              22 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            itemCount: stats.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, index) => Text(stats[index],
                style: const TextStyle(fontSize: 9, color: Color(0xFFB8B6B2))),
          ),
        ),
      ]),
    );
  }
}
