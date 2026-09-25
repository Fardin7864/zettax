import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:primevest_mobile/features/onboarding/reference_landing_screen.dart';

void main() {
  testWidgets('redesigned landing page has no layout overflow across screens',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    for (final width in <double>[320, 360, 390, 430, 768, 1024, 1440]) {
      tester.view.physicalSize = Size(width, 850);
      await tester.pumpWidget(ProviderScope(
          key: ValueKey(width),
          child: const MaterialApp(home: WebLandingScreen())));
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull, reason: 'width $width');
      expect(find.byKey(const Key('navbar-download')), findsOneWidget);
    }
  });

  testWidgets(
      'navbar keeps the primary download action visible at all target widths',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    for (final width in <double>[
      320,
      360,
      375,
      390,
      393,
      412,
      430,
      768,
      1024,
      1440
    ]) {
      tester.view.physicalSize = Size(width, 800);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: LandingNavbar(
          compact: width < 1340,
          onMarkets: () {},
          onFeatures: () {},
          onHowItWorks: () {},
          onDemo: () {},
          onLearn: () {},
          onFaq: () {},
          onLogin: () {},
          onTryDemo: () {},
          onDownload: () {},
        )),
      ));
      await tester.pump();
      final download = find.byKey(const Key('navbar-download'));
      expect(download, findsOneWidget, reason: 'width $width');
      final rect = tester.getRect(download);
      expect(rect.left, greaterThanOrEqualTo(0), reason: 'width $width');
      expect(rect.right, lessThanOrEqualTo(width), reason: 'width $width');
      expect(rect.height, greaterThanOrEqualTo(44), reason: 'width $width');
      expect(find.byKey(const Key('navbar-menu')),
          width < 1340 ? findsOneWidget : findsNothing);
      expect(tester.takeException(), isNull, reason: 'width $width');
    }
  });

  testWidgets('mobile navbar remains usable with larger text', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
        child: Scaffold(
            body: LandingNavbar(
          compact: true,
          onMarkets: () {},
          onFeatures: () {},
          onHowItWorks: () {},
          onDemo: () {},
          onLearn: () {},
          onFaq: () {},
          onLogin: () {},
          onTryDemo: () {},
          onDownload: () {},
        )),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(tester.getRect(find.byKey(const Key('navbar-download'))).right,
        lessThanOrEqualTo(320));
    await tester.tap(find.byKey(const Key('navbar-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Try Demo Trading'), findsOneWidget);
  });

  testWidgets('landing page keeps its hero and download visible on desktop',
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
      find.text('Explore Global Markets'),
      700,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('navbar-download')), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(const Key('navbar-download'))).dy,
        lessThan(80));
    expect(tester.getSize(find.text('Explore Global Markets')).width,
        greaterThan(250));
    expect(find.byKey(const Key('navbar-download')), findsOneWidget);
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
    expect(find.text('Try Demo Trading'), findsWidgets);
    expect(find.byKey(const Key('navbar-download')), findsOneWidget);
  });
}
