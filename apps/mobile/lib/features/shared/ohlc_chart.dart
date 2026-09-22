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
  });

  factory ChartCandle.fromMarket(MarketCandle candle) => ChartCandle(
        time: candle.openTime,
        open: candle.open,
        high: candle.high,
        low: candle.low,
        close: candle.close,
      );

  final DateTime time;
  final double open;
  final double high;
  final double low;
  final double close;
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
            final candleWidth = _canvasWidth / max(1, nextVisible);
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
              height: widget.compact ? 190 : 270,
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
    const topPadding = 28.0;
    const bottomPadding = 12.0;
    final chartHeight = size.height - topPadding - bottomPadding;
    var minPrice = visible.map((candle) => candle.low).reduce(min);
    var maxPrice = visible.map((candle) => candle.high).reduce(max);
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
      canvas.drawLine(Offset(0, position), Offset(size.width, position), grid);
    }

    final timeline = _CandleTimeline(visible, size.width);
    double candleX(int index) => lineMode && index == visible.length - 1
        ? timeline.xFor(DateTime.fromMillisecondsSinceEpoch(
            min(DateTime.now().millisecondsSinceEpoch, timeline.latestTime)))
        : timeline.candleX(index);
    final bodyWidth = timeline.bodyWidth;
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
          ..strokeWidth = max(1.0, bodyWidth * .16);
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
      : left = 8,
        right = max(8, width - 8) {
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
    final futureSlots = max(6, (candles.length * .5).round());
    firstTime = candles.first.time.millisecondsSinceEpoch;
    finalTime = latestTime + sampleStep * futureSlots;
    timeRange = max(1, finalTime - firstTime);
    final spacing = candles.length > 1
        ? (xFor(candles[1].time) - xFor(candles[0].time)).abs()
        : (right - left) / (futureSlots + 1);
    bodyWidth = max(2.0, min(11.0, spacing * .58));
  }

  final List<ChartCandle> candles;
  final double width;
  final double left;
  final double right;
  late final int firstTime;
  late final int latestTime;
  late final int finalTime;
  late final int sampleStep;
  late final int timeRange;
  late final double bodyWidth;

  double xFor(DateTime time) => (left +
          (time.millisecondsSinceEpoch - firstTime) /
              timeRange *
              (right - left))
      .clamp(left, right);

  double candleX(int index) => xFor(candles[index].time);
}
