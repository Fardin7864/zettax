import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:primevest_mobile/features/onboarding/web_landing_screen.dart';

void main() {
  testWidgets('landing page keeps its download heading readable on desktop',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: WebLandingScreen())));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.scrollUntilVisible(
      find.text('Your workspace, wherever you are.'),
      700,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.text('Your workspace, wherever you are.')).width,
        greaterThan(250));
    expect(find.text('Download for Android'), findsOneWidget);
  });

  testWidgets('landing page exposes demo and download actions on a phone',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: WebLandingScreen())));
    await tester.pump(const Duration(milliseconds: 700));

    expect(tester.takeException(), isNull);
    expect(find.text('Start demo trading'), findsOneWidget);
    expect(find.text('Download Android app'), findsOneWidget);
  });
}
