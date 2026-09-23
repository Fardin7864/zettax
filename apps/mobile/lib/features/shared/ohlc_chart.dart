import 'dart:math';

import 'package:flutter/material.dart';
import 'package:primevest_mobile/market/market_data_api.dart';

class ChartCandle {
  const ChartCandle({
    required this.time,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    this.volume,
  });

  factory ChartCandle.fromMarket(MarketCandle candle) => ChartCandle(
        time: candle.openTime,
        open: candle.open,
        high: candle.high,
        low: candle.low,
        close: candle.close,
        volume: candle.volume,
      );

  final DateTime time;
  final double open;
  final double high;
  final double low;
  final double close;
  final double? volume;
}

double? candleAverage(List<ChartCandle> candles, int index, int period,
    {bool volume = false}) {
  if (period <= 0 || index < period - 1 || index >= candles.length) return null;
  var sum = 0.0;
  for (var i = index - period + 1; i <= index; i++) {
    final value = volume ? candles[i].volume : candles[i].close;
    if (value == null || !value.isFinite) return null;
    sum += value;
  }
  return sum / period;
}

double chartBodyWidth(double viewportWidth, int visibleCount) {
  final plotWidth = max(0.0, viewportWidth - 64);
  return max(1.0, plotWidth / max(1, visibleCount) * .98);
}

class ChartTradeMarker {
  const ChartTradeMarker({
    required this.id,
    required this.openedAt,
    required this.price,
    required this.label,
    this.endsAt,
    this.color = const Color(0xFF22C55E),
  });

  final String id;
  final DateTime openedAt;
  final DateTime? endsAt;
  final double price;
  final String label;
  final Color color;
}

class OhlcChart extends StatefulWidget {
  const OhlcChart({
    super.key,
    required this.candles,
    required this.precision,
    this.compact = false,
    this.onSelectionChanged,
    this.onViewportChanged,
    this.onLoadOlder,
    this.tradeMarkers = const [],
    this.lineMode = false,
  });

  final List<ChartCandle> candles;
  final int precision;
  final bool compact;
  final ValueChanged<ChartCandle?>? onSelectionChanged;
  final void Function(int startIndex, int endIndex)? onViewportChanged;
  final VoidCallback? onLoadOlder;
  final List<ChartTradeMarker> tradeMarkers;
  final bool lineMode;

  @override
  State<OhlcChart> createState() => _OhlcChartState();
}

class _OhlcChartState extends State<OhlcChart> {
  int visibleCount = 42;
  int endIndex = 0;
  int? selectedIndex;
  int _scaleStartVisible = 42;
  int _scaleStartEnd = 0;
  Offset _scaleStartFocal = Offset.zero;
  double _canvasWidth = 1;

  @override
  void initState() {
    super.initState();
    _resetViewport();
  }

  @override
  void didUpdateWidget(covariant OhlcChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    final addedToFront = widget.candles.length > oldWidget.candles.length &&
        oldWidget.candles.isNotEmpty &&
        widget.candles.last.time == oldWidget.candles.last.time;
    if (addedToFront) {
      endIndex += widget.candles.length - oldWidget.candles.length;
      selectedIndex = selectedIndex == null
          ? null
          : selectedIndex! + widget.candles.length - oldWidget.candles.length;
    } else if (oldWidget.candles.length != widget.candles.length ||
        oldWidget.candles.lastOrNull?.time != widget.candles.lastOrNull?.time) {
      _resetViewport();
    }
  }

  void _resetViewport() {
    endIndex = widget.candles.length;
    visibleCount = min(42, max(1, widget.candles.length));
    selectedIndex = null;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.candles.isEmpty) return const SizedBox.shrink();
    return Semantics(
      label:
          'Interactive candlestick chart. Pinch to zoom, drag horizontally to pan, and tap a candle for OHLC values.',
      value: selectedIndex == null
          ? null
          : _selectionDescription(widget.candles[selectedIndex!]),
      child: LayoutBuilder(builder: (context, constraints) {
        _canvasWidth = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleStart: (details) {
            _scaleStartVisible = visibleCount;
            _scaleStartEnd = endIndex;
            _scaleStartFocal = details.localFocalPoint;
          },
          onScaleUpdate: (details) {
            final maxVisible = widget.candles.length;
            final minimum = min(8, maxVisible);
            final nextVisible =
                (_scaleStartVisible / details.scale).round().clamp(
                      minimum,
                      maxVisible,
                    );
            final candleWidth = max(1.0, (_canvasWidth - 64) / nextVisible);
            final movedCandles =
                ((details.localFocalPoint.dx - _scaleStartFocal.dx) /
                        candleWidth)
                    .round();
            final nextEnd = (_scaleStartEnd - movedCandles).clamp(
              nextVisible,
              widget.candles.length,
            );
            setState(() {
              visibleCount = nextVisible;
              endIndex = nextEnd;
              selectedIndex = null;
            });
            widget.onSelectionChanged?.call(null);
            widget.onViewportChanged?.call(endIndex - visibleCount, endIndex);
            if (endIndex == visibleCount && movedCandles > 0) {
              widget.onLoadOlder?.call();
            }
          },
          onTapDown: (details) {
            final start = max(0, endIndex - visibleCount);
            final visible = widget.candles.sublist(start, endIndex);
            final timeline = _CandleTimeline(visible, _canvasWidth);
            var local = 0;
            var nearestDistance = double.infinity;
            for (var index = 0; index < visible.length; index++) {
              final distance =
                  (timeline.candleX(index) - details.localPosition.dx).abs();
              if (distance < nearestDistance) {
                nearestDistance = distance;
                local = index;
              }
            }
            setState(() {
              selectedIndex = start + local;
            });
            widget.onSelectionChanged?.call(widget.candles[selectedIndex!]);
          },
          child: CustomPaint(
            painter: _CandlePainter(
              candles: widget.candles,
              startIndex: max(0, endIndex - visibleCount),
              endIndex: endIndex,
              selectedIndex: selectedIndex,
              precision: widget.precision,
              tradeMarkers: widget.tradeMarkers,
              lineMode: widget.lineMode,
            ),
            child: SizedBox(
              width: double.infinity,
              height: constraints.hasBoundedHeight
                  ? constraints.maxHeight
                  : (widget.compact ? 190 : 270),
            ),
          ),
        );
      }),
    );
  }

  String _selectionDescription(ChartCandle candle) =>
      'Open ${candle.open.toStringAsFixed(widget.precision)}, '
      'high ${candle.high.toStringAsFixed(widget.precision)}, '
      'low ${candle.low.toStringAsFixed(widget.precision)}, '
      'close ${candle.close.toStringAsFixed(widget.precision)}';
}

class _CandlePainter extends CustomPainter {
  const _CandlePainter({
    required this.candles,
    required this.startIndex,
    required this.endIndex,
    required this.selectedIndex,
    required this.precision,
    required this.tradeMarkers,
    required this.lineMode,
  });

  final List<ChartCandle> candles;
  final int startIndex;
  final int endIndex;
  final int? selectedIndex;
  final int precision;
  final List<ChartTradeMarker> tradeMarkers;
  final bool lineMode;

  @override
  void paint(Canvas canvas, Size size) {
    final visible = candles.sublist(startIndex, endIndex);
    if (visible.isEmpty) return;
    const topPadding = 20.0;
    const bottomPadding = 20.0;
    final hasVolume = visible.any((candle) => candle.volume != null);
    final volumeHeight = hasVolume ? max(44.0, size.height * .18) : 0.0;
    final chartHeight =
        max(40.0, size.height - topPadding - bottomPadding - volumeHeight);
    var minPrice = visible.map((candle) => candle.low).reduce(min);
    var maxPrice = visible.map((candle) => candle.high).reduce(max);
    // Include the visible MA values in the scale so all three overlays stay
    // inside the price panel even when the viewport is zoomed into a trend.
    for (final period in [7, 25, 99]) {
      for (var index = startIndex; index < endIndex; index++) {
        final average = candleAverage(candles, index, period);
        if (average == null) continue;
        minPrice = min(minPrice, average);
        maxPrice = max(maxPrice, average);
      }
    }
    final rawRange = maxPrice - minPrice;
    final padding =
        rawRange == 0 ? maxPrice.abs() * .002 + .00001 : rawRange * .08;
    minPrice -= padding;
    maxPrice += padding;
    final range = maxPrice - minPrice;
    double y(double price) =>
        topPadding + (maxPrice - price) / range * chartHeight;

    final grid = Paint()
      ..color = const Color(0xFF34312D)
      ..strokeWidth = 1;
    for (var row = 0; row <= 4; row++) {
      final position = topPadding + chartHeight * row / 4;
      canvas.drawLine(
          Offset(0, position), Offset(size.width - 62, position), grid);
      _label(
          canvas, maxPrice - range * row / 4, Offset(size.width, position - 6),
          precision: precision);
    }

    final timeline = _CandleTimeline(visible, size.width);
    double candleX(int index) => lineMode && index == visible.length - 1
        ? timeline.xFor(DateTime.fromMillisecondsSinceEpoch(
            min(DateTime.now().millisecondsSinceEpoch, timeline.latestTime)))
        : timeline.candleX(index);
    final bodyWidth = timeline.bodyWidth;
    if (endIndex == candles.length) {
      final lastPrice = candles.last.close;
      final priceY = y(lastPrice);
      final currentPaint = Paint()
        ..color = const Color(0xFFB4C5D8)
        ..strokeWidth = 1;
      for (var x = timeline.left; x < timeline.right; x += 8) {
        canvas.drawLine(Offset(x, priceY),
            Offset(min(x + 4, timeline.right), priceY), currentPaint);
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(size.width - 62, priceY - 10, 62, 20),
            const Radius.circular(4)),
        Paint()..color = const Color(0xFFB4C5D8),
      );
      _label(canvas, lastPrice, Offset(size.width, priceY - 7),
          precision: precision, dark: true);
    }

    for (final (period, color) in [
      (7, const Color(0xFFF6C342)),
      (25, const Color(0xFFEF5DA8)),
      (99, const Color(0xFFA78BFA)),
    ]) {
      final path = Path();
      var started = false;
      for (var index = 0; index < visible.length; index++) {
        final average = candleAverage(candles, startIndex + index, period);
        if (average == null) continue;
        final point = Offset(timeline.candleX(index), y(average));
        if (!started) {
          path.moveTo(point.dx, point.dy);
          started = true;
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      if (started) {
        canvas.drawPath(
            path,
            Paint()
              ..color = color
              ..strokeWidth = 1.4
              ..style = PaintingStyle.stroke);
      }
    }
    if (lineMode) {
      final line = Path();
      for (var index = 0; index < visible.length; index++) {
        final point = Offset(candleX(index), y(visible[index].close));
        index == 0
            ? line.moveTo(point.dx, point.dy)
            : line.lineTo(point.dx, point.dy);
      }
      final area = Path.from(line)
        ..lineTo(candleX(visible.length - 1), size.height - bottomPadding)
        ..lineTo(candleX(0), size.height - bottomPadding)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x55F8B425), Color(0x00F8B425)],
          ).createShader(Offset.zero & size),
      );
      canvas.drawPath(
        line,
        Paint()
          ..color = const Color(0xFFF8B425)
          ..strokeWidth = 2.2
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round,
      );
      final last = Offset(candleX(visible.length - 1), y(visible.last.close));
      canvas.drawLine(
        Offset(0, last.dy),
        Offset(size.width, last.dy),
        Paint()
          ..color = const Color(0x66F8B425)
          ..strokeWidth = 1,
      );
      canvas.drawCircle(last, 4, Paint()..color = const Color(0xFFF8B425));
    } else {
      for (var index = 0; index < visible.length; index++) {
        final candle = visible[index];
        final x = candleX(index);
        final positive = candle.close >= candle.open;
        final color =
            positive ? const Color(0xFF22C55E) : const Color(0xFFF87171);
        final paint = Paint()
          ..color = color
          ..strokeWidth = 1.15;
        final openY = y(candle.open);
        final closeY = y(candle.close);
        final top = min(openY, closeY);
        final bottom = max(openY, closeY);
        final wickTop = min(y(candle.high), top - 3).clamp(
          topPadding,
          size.height - bottomPadding,
        );
        final wickBottom = max(y(candle.low), bottom + 3).clamp(
          topPadding,
          size.height - bottomPadding,
        );
        canvas.drawLine(
          Offset(x, wickTop),
          Offset(x, wickBottom),
          paint,
        );
        canvas.drawRect(
          Rect.fromLTRB(x - bodyWidth / 2, top, x + bodyWidth / 2,
              max(top + 1.5, bottom)),
          paint,
        );
      }
    }

    if (hasVolume) {
      final volumeTop = topPadding + chartHeight + 10;
      final volumeBottom = size.height - bottomPadding;
      final maxVolume =
          max(1.0, visible.map((candle) => candle.volume ?? 0).reduce(max));
      for (var index = 0; index < visible.length; index++) {
        final volume = visible[index].volume;
        if (volume == null) continue;
        final height = (volume / maxVolume * (volumeBottom - volumeTop))
            .clamp(0.0, volumeBottom - volumeTop);
        final up = visible[index].close >= visible[index].open;
        canvas.drawRect(
          Rect.fromLTWH(timeline.candleX(index) - bodyWidth / 2,
              volumeBottom - height, bodyWidth, height),
          Paint()
            ..color = up ? const Color(0x9930B68C) : const Color(0x99D84E6A),
        );
      }
      for (final (period, color) in [
        (5, const Color(0xFFF6C342)),
        (10, const Color(0xFFA78BFA)),
      ]) {
        final path = Path();
        var started = false;
        for (var index = 0; index < visible.length; index++) {
          final average =
              candleAverage(candles, startIndex + index, period, volume: true);
          if (average == null) continue;
          final point = Offset(timeline.candleX(index),
              volumeBottom - average / maxVolume * (volumeBottom - volumeTop));
          if (!started) {
            path.moveTo(point.dx, point.dy);
            started = true;
          } else {
            path.lineTo(point.dx, point.dy);
          }
        }
        if (started) {
          canvas.drawPath(
              path,
              Paint()
                ..color = color
                ..strokeWidth = 1.2
                ..style = PaintingStyle.stroke);
        }
      }
      _text(
          canvas,
          'VOL ${_compact(visible.last.volume ?? 0)}  MA(5) ${_compact(candleAverage(candles, endIndex - 1, 5, volume: true))}  MA(10) ${_compact(candleAverage(candles, endIndex - 1, 10, volume: true))}',
          Offset(6, volumeTop - 10),
          const Color(0xFFD5C6AD),
          9);
    }

    _text(canvas, _time(visible.first.time), Offset(6, size.height - 14),
        const Color(0xFF92969F), 9);
    _text(
        canvas,
        _time(visible.last.time),
        Offset(max(6, timeline.right - 83), size.height - 14),
        const Color(0xFF92969F),
        9);

    for (var markerIndex = 0;
        markerIndex < tradeMarkers.length;
        markerIndex++) {
      final marker = tradeMarkers[markerIndex];
      if (marker.price < minPrice || marker.price > maxPrice) continue;
      final startX = timeline.xFor(marker.openedAt);
      final endX = marker.endsAt == null
          ? timeline.right
          : timeline.xFor(marker.endsAt!);
      final markerY = y(marker.price);
      final markerPaint = Paint()
        ..color = marker.color.withValues(alpha: .88)
        ..strokeWidth = 1.6;
      canvas.drawLine(
        Offset(startX, markerY),
        Offset(max(startX + 4, endX), markerY),
        markerPaint,
      );
      if (marker.endsAt != null) {
        canvas.drawLine(
          Offset(endX, topPadding),
          Offset(endX, size.height - bottomPadding),
          Paint()
            ..color = marker.color.withValues(alpha: .45)
            ..strokeWidth = 1.4,
        );
      }
      canvas.drawCircle(
        Offset(startX, markerY),
        4.5,
        Paint()..color = marker.color,
      );
      final markerLabel = TextPainter(
        text: TextSpan(
          text: '${marker.label}  ${marker.price.toStringAsFixed(precision)}',
          style: TextStyle(
            color: marker.color,
            fontSize: 9,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: size.width - 16);
      final labelY = (markerY - 17 - (markerIndex % 3) * 12)
          .clamp(topPadding, size.height - 16);
      markerLabel.paint(
          canvas,
          Offset(
              (startX + 6).clamp(8, max(8, size.width - markerLabel.width - 8)),
              labelY));
    }

    final selected = selectedIndex;
    if (selected == null || selected < startIndex || selected >= endIndex) {
      return;
    }
    final relative = selected - startIndex;
    final candle = candles[selected];
    final x = candleX(relative);
    final crosshair = Paint()
      ..color = const Color(0xB3FFFFFF)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(x, topPadding), Offset(x, size.height), crosshair);
    canvas.drawLine(
      Offset(0, y(candle.close)),
      Offset(size.width, y(candle.close)),
      crosshair,
    );
    final label = TextPainter(
      text: TextSpan(
        text: 'O ${candle.open.toStringAsFixed(precision)}   '
            'H ${candle.high.toStringAsFixed(precision)}   '
            'L ${candle.low.toStringAsFixed(precision)}   '
            'C ${candle.close.toStringAsFixed(precision)}',
        style: const TextStyle(
          color: Color(0xFFE7E5E4),
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: size.width - 8);
    label.paint(canvas, const Offset(6, 6));
  }

  void _label(Canvas canvas, double value, Offset offset,
      {required int precision, bool dark = false}) {
    final painter = TextPainter(
      text: TextSpan(
        text: value.toStringAsFixed(precision),
        style: TextStyle(
          color: dark ? const Color(0xFF16202B) : const Color(0xFFAAB0BA),
          fontSize: 9,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    painter.paint(canvas, Offset(offset.dx - painter.width, offset.dy));
  }

  double _text(Canvas canvas, String value, Offset offset, Color color,
      double fontSize) {
    final painter = TextPainter(
      text: TextSpan(
          text: value,
          style: TextStyle(
              color: color, fontSize: fontSize, fontWeight: FontWeight.w600)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    painter.paint(canvas, offset);
    return painter.width;
  }

  String _compact(double? value) {
    if (value == null) return '—';
    if (value >= 1000000000) {
      return '${(value / 1000000000).toStringAsFixed(2)}B';
    }
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(2)}M';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(2)}K';
    return value.toStringAsFixed(2);
  }

  String _time(DateTime time) =>
      '${time.month.toString().padLeft(2, '0')}/${time.day.toString().padLeft(2, '0')} '
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  @override
  bool shouldRepaint(covariant _CandlePainter oldDelegate) =>
      oldDelegate.candles != candles ||
      oldDelegate.startIndex != startIndex ||
      oldDelegate.endIndex != endIndex ||
      oldDelegate.selectedIndex != selectedIndex ||
      oldDelegate.tradeMarkers != tradeMarkers ||
      oldDelegate.lineMode != lineMode;
}

class _CandleTimeline {
  _CandleTimeline(this.candles, this.width)
      : left = 2,
        right = max(2, width - 62) {
    final lastTime = candles.last.time.millisecondsSinceEpoch;
    sampleStep = candles.length > 1
        ? max(
            1,
            lastTime - candles[candles.length - 2].time.millisecondsSinceEpoch,
          )
        : 60000;
    latestTime = min(
      DateTime.now().millisecondsSinceEpoch,
      lastTime + sampleStep,
    );
    spacing = (right - left) / max(1, candles.length);
    bodyWidth = chartBodyWidth(width, candles.length);
  }

  final List<ChartCandle> candles;
  final double width;
  final double left;
  final double right;
  late final int latestTime;
  late final int sampleStep;
  late final double bodyWidth;
  late final double spacing;

  double xFor(DateTime time) {
    final target = time.millisecondsSinceEpoch;
    if (target <= candles.first.time.millisecondsSinceEpoch) return candleX(0);
    for (var index = 1; index < candles.length; index++) {
      final previous = candles[index - 1].time.millisecondsSinceEpoch;
      final next = candles[index].time.millisecondsSinceEpoch;
      if (target <= next) {
        final fraction = (target - previous) / max(1, next - previous);
        return candleX(index - 1) + spacing * fraction;
      }
    }
    final extra = (target - candles.last.time.millisecondsSinceEpoch) /
        sampleStep *
        spacing;
    return (candleX(candles.length - 1) + extra).clamp(left, right);
  }

  double candleX(int index) => left + spacing * (index + .5);
}
