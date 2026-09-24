import 'package:flutter/material.dart';
import 'package:primevest_mobile/market/market_data_api.dart';

class MarketReturnWindow {
  const MarketReturnWindow(this.label, this.days);
  final String label;
  final int days;
}

const marketReturnWindows = <MarketReturnWindow>[
  MarketReturnWindow('Today', 0),
  MarketReturnWindow('7 Days', 7),
  MarketReturnWindow('30 Days', 30),
  MarketReturnWindow('90 Days', 90),
  MarketReturnWindow('180 Days', 180),
  MarketReturnWindow('1 Year', 365),
];

/// Observed movement across contiguous one-minute candles. Missing bars are
/// unavailable, never interpolated or borrowed from a wider interval.
({double amount, double percent})? marketMinuteMove(
    MarketCandleSeries? series, int minutes) {
  if (series == null ||
      series.effectiveInterval != '1m' ||
      minutes < 1 ||
      series.candles.length < minutes) {
    return null;
  }
  final candles = series.candles;
  final first = candles[candles.length - minutes];
  final last = candles.last;
  for (var index = candles.length - minutes + 1;
      index < candles.length;
      index++) {
    if (candles[index].openTime.difference(candles[index - 1].openTime) !=
        const Duration(minutes: 1)) {
      return null;
    }
  }
  if (first.open <= 0 || !first.open.isFinite || !last.close.isFinite) {
    return null;
  }
  final amount = last.close - first.open;
  return (amount: amount, percent: amount / first.open * 100);
}

/// Change from the observed UTC daily open on the requested calendar date.
/// Missing dates deliberately return null; no earlier price is substituted.
double? marketPeriodReturn(
  List<MarketCandle> dailyCandles,
  double currentPrice,
  DateTime asOf,
  int days,
) {
  if (days < 0 || currentPrice <= 0 || !currentPrice.isFinite) return null;
  final utc = asOf.toUtc();
  final day =
      DateTime.utc(utc.year, utc.month, utc.day).subtract(Duration(days: days));
  for (final candle in dailyCandles.reversed) {
    final openTime = candle.openTime.toUtc();
    if (openTime.isBefore(day)) break;
    if (!openTime.isBefore(day.add(const Duration(days: 1))) &&
        !openTime.isAtSameMomentAs(day)) {
      continue;
    }
    if (candle.open <= 0 || !candle.open.isFinite) return null;
    return (currentPrice / candle.open - 1) * 100;
  }
  return null;
}

class MarketPerformanceStrip extends StatelessWidget {
  const MarketPerformanceStrip({
    super.key,
    required this.history,
    required this.latestPrice,
    required this.asOf,
    this.minuteSeries,
    this.precision = 2,
    this.loading = false,
  });

  final MarketCandleSeries? history;
  final double? latestPrice;
  final DateTime? asOf;
  final MarketCandleSeries? minuteSeries;
  final int precision;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final candles = history?.candles ?? const <MarketCandle>[];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(
        padding: EdgeInsets.only(left: 6, bottom: 2),
        child: Text('Observed 1m/15m bars · UTC daily change',
            style: TextStyle(fontSize: 9, color: Color(0xFFAAA7A2))),
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final minutes in [1, 15])
              SizedBox(
                  width: 98,
                  child: Builder(builder: (context) {
                    final move = marketMinuteMove(minuteSeries, minutes);
                    final color = move == null
                        ? const Color(0xFFAAA7A2)
                        : move.amount >= 0
                            ? const Color(0xFF31C691)
                            : const Color(0xFFF87171);
                    final sign = move != null && move.amount > 0 ? '+' : '';
                    return Tooltip(
                      message:
                          'Observed change across $minutes contiguous one-minute ${minutes == 1 ? 'bar' : 'bars'}',
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${minutes}m',
                                style: const TextStyle(
                                    fontSize: 9, color: Color(0xFFAAA7A2))),
                            Text(
                                move == null
                                    ? '—'
                                    : '$sign${move.amount.toStringAsFixed(precision)} · $sign${move.percent.toStringAsFixed(2)}%',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 10, color: color)),
                          ]),
                    );
                  })),
            for (final window in marketReturnWindows)
              SizedBox(
                  width: 72,
                  child: Builder(builder: (context) {
                    final change = latestPrice == null || asOf == null
                        ? null
                        : marketPeriodReturn(
                            candles, latestPrice!, asOf!, window.days);
                    final value = change == null
                        ? '—'
                        : change.abs() < .005
                            ? '0.00%'
                            : '${change >= 0 ? '+' : ''}${change.toStringAsFixed(2)}%';
                    final color = change == null
                        ? const Color(0xFFAAA7A2)
                        : change >= 0
                            ? const Color(0xFF31C691)
                            : const Color(0xFFF87171);
                    return Tooltip(
                      message:
                          'Change since ${window.days == 0 ? 'today’s' : '${window.days}-day'} UTC daily open',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(window.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 9, color: Color(0xFFAAA7A2))),
                          Text(loading ? '…' : value,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11, color: color)),
                        ],
                      ),
                    );
                  })),
          ]),
        ),
      ),
    ]);
  }
}
