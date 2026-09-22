import 'package:flutter/material.dart';
import 'package:primevest_mobile/features/shared/ohlc_chart.dart';
import 'package:primevest_mobile/market/market_data_api.dart';

/// Live OHLC presentation backed by the existing market and trade data.
class LiveTradeChart extends StatelessWidget {
  const LiveTradeChart({
    super.key,
    required this.series,
    required this.precision,
    this.markers = const [],
  });

  final MarketCandleSeries series;
  final int precision;
  final List<ChartTradeMarker> markers;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: OhlcChart(
          candles: series.candles.map(ChartCandle.fromMarket).toList(),
          precision: precision,
          tradeMarkers: markers,
        ),
      );
}
