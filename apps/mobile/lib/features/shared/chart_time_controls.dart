import 'package:flutter/material.dart';
import 'dart:ui' show PointerDeviceKind;
import 'package:primevest_mobile/app/design_system.dart';

typedef ChartTimeOption = ({String id, String label, String description});

class ChartTimeMenu extends StatelessWidget {
  const ChartTimeMenu(
      {super.key,
      required this.value,
      required this.options,
      required this.onSelected});
  final String value;
  final List<ChartTimeOption> options;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final selected = options.firstWhere((option) => option.id == value);
    return PopupMenuButton<String>(
      initialValue: value,
      tooltip: 'Change chart timeframe',
      onSelected: onSelected,
      itemBuilder: (_) => options
          .map((option) => CheckedPopupMenuItem<String>(
              value: option.id,
              checked: option.id == value,
              child: Text(option.description)))
          .toList(),
      child: Container(
        constraints: const BoxConstraints(minHeight: 40),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
            color: PrimeVestDesignSystem.primaryGold.withValues(alpha: .12),
            border: Border.all(
                color: PrimeVestDesignSystem.primaryGold.withValues(alpha: .6)),
            borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.candlestick_chart_outlined,
              size: 16, color: PrimeVestDesignSystem.primaryGold),
          const SizedBox(width: 5),
          Text('Chart · ${selected.label}',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: PrimeVestDesignSystem.primaryGold)),
          const Icon(Icons.expand_more,
              size: 20, color: PrimeVestDesignSystem.primaryGold),
        ]),
      ),
    );
  }
}

class ChartTimeStrip extends StatefulWidget {
  const ChartTimeStrip(
      {super.key,
      required this.value,
      required this.options,
      required this.onSelected});
  final String value;
  final List<ChartTimeOption> options;
  final ValueChanged<String> onSelected;

  @override
  State<ChartTimeStrip> createState() => _ChartTimeStripState();
}

class _ChartTimeStripState extends State<ChartTimeStrip> {
  final selectedKey = GlobalKey();
  @override
  void initState() {
    super.initState();
    _revealSelected();
  }

  @override
  void didUpdateWidget(ChartTimeStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _revealSelected();
  }

  void _revealSelected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || selectedKey.currentContext == null) return;
      Scrollable.ensureVisible(selectedKey.currentContext!,
          alignment: .5, duration: const Duration(milliseconds: 180));
    });
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 40,
        child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(dragDevices: {
              PointerDeviceKind.touch,
              PointerDeviceKind.mouse,
              PointerDeviceKind.stylus,
              PointerDeviceKind.trackpad
            }),
            child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6),
                      child: Center(
                          child: Text('Chart',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: PrimeVestDesignSystem.textMuted)))),
                  for (final option in widget.options)
                    Padding(
                        key: widget.value == option.id ? selectedKey : null,
                        padding: const EdgeInsets.only(right: 5),
                        child: Tooltip(
                            message: 'Chart: ${option.description}',
                            child: TextButton(
                              key: ValueKey('chart-time-${option.id}'),
                              onPressed: () => widget.onSelected(option.id),
                              style: TextButton.styleFrom(
                                  minimumSize: const Size(42, 36),
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 8),
                                  backgroundColor: widget.value == option.id
                                      ? PrimeVestDesignSystem.primaryGold
                                          .withValues(alpha: .2)
                                      : const Color(0xFF332D25),
                                  foregroundColor: widget.value == option.id
                                      ? PrimeVestDesignSystem.primaryGold
                                      : PrimeVestDesignSystem.textMuted,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8))),
                              child: Text(option.label,
                                  style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700)),
                            ))),
                ]))),
      );
}
