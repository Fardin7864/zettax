import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:primevest_mobile/features/shared/chart_time_controls.dart';

final options = [
  for (final id in [
    '1m',
    '5m',
    '15m',
    '1h',
    '1d',
    '1W',
    '1M',
    '6M',
    '1Y',
    '3Y',
    '5Y'
  ])
    (id: id, label: id, description: 'Period $id')
];

class Harness extends StatefulWidget {
  const Harness({super.key});
  @override
  State<Harness> createState() => _HarnessState();
}

class _HarnessState extends State<Harness> {
  String value = '1m';
  @override
  Widget build(BuildContext context) => MaterialApp(
          home: Scaffold(
              body: Column(children: [
        ChartTimeMenu(
            value: value,
            options: options,
            onSelected: (id) => setState(() => value = id)),
        ChartTimeStrip(
            value: value,
            options: options,
            onSelected: (id) => setState(() => value = id)),
      ])));
}

void main() {
  testWidgets(
      'top menu and bottom row select the same timeframe and reveal the selection',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const Harness());
    await tester.pumpAndSettle();
    expect(find.text('Chart · 1m'), findsOneWidget);
    await tester.tap(find.byTooltip('Change chart timeframe'));
    await tester.pumpAndSettle();
    final lastMenuItem = find.ancestor(
        of: find.text('Period 5Y'),
        matching: find.byType(CheckedPopupMenuItem<String>));
    await tester.ensureVisible(lastMenuItem);
    await tester.pumpAndSettle();
    await tester.tap(lastMenuItem);
    await tester.pumpAndSettle();
    expect(find.text('Chart · 5Y'), findsOneWidget);
    expect(find.byKey(const ValueKey('chart-time-5Y')).hitTestable(),
        findsOneWidget);
    await tester.drag(find.byType(SingleChildScrollView), const Offset(600, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chart-time-5m')));
    await tester.pumpAndSettle();
    expect(find.text('Chart · 5m'), findsOneWidget);
    await tester.drag(
        find.byType(SingleChildScrollView), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chart-time-5Y')).hitTestable(),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('every timeframe button invokes its own option without overflow',
      (tester) async {
    for (final option in options) {
      String? selected;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SizedBox(
                  width: 320,
                  child: ChartTimeStrip(
                      key: ValueKey(option.id),
                      value: option.id,
                      options: options,
                      onSelected: (id) => selected = id)))));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('chart-time-${option.id}')));
      expect(selected, option.id);
      expect(tester.takeException(), isNull);
    }
  });
}
