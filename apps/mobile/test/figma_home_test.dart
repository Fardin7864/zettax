import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:primevest_mobile/app/design_system.dart';
import 'package:primevest_mobile/core/app_providers.dart';
import 'package:primevest_mobile/core/auth/auth_models.dart';
import 'package:primevest_mobile/core/auth/token_store.dart';
import 'package:primevest_mobile/demo/providers.dart';
import 'package:primevest_mobile/features/home/figma_home_page.dart';
import 'package:primevest_mobile/features/home/home_data.dart';

class EmptyTokens implements TokenStore {
  @override
  Future<void> clearTokens() async {}
  @override
  Future<void> writeTokens(SessionTokens tokens) async {}
  @override
  Future<SessionTokens?> readTokens() async => null;
  @override
  Future<DeviceMetadata> deviceMetadata() async => const DeviceMetadata(
      deviceFingerprint: 'home-test',
      deviceName: 'test',
      devicePlatform: 'test');
}

void main() {
  final now = DateTime.utc(2026, 11, 6, 12);
  Map<String, Object> row(int days, int value) => {
        'value': '$value',
        'timestamp':
            '${now.subtract(Duration(days: days)).millisecondsSinceEpoch ~/ 1000}'
      };
  test('sentiment history uses calendar dates and validates freshness', () {
    final result = HomeSentiment.fromJson({
      'data': [row(7, 39), row(0, 64), row(1, 61)]
    }, now: now);
    expect(result.value, 64);
    expect(result.classification, 'Greed');
    expect(result.yesterday, 61);
    expect(result.lastWeek, 39);
    expect(
        HomeSentiment.fromJson({
          'data': [row(0, 64), row(2, 50)]
        }, now: now)
            .yesterday,
        isNull);
    for (final data in [
      [row(3, 64)],
      [row(0, 101)],
      <Object>[]
    ]) {
      expect(() => HomeSentiment.fromJson({'data': data}, now: now),
          throwsFormatException);
    }
  });
  for (final size in [
    const Size(402, 874),
    const Size(360, 791),
    const Size(320, 720)
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('Home adapts to ${size.width} at text scale $scale',
          (tester) async {
        tester.view.physicalSize = size * 2;
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        for (final name in ['DMSans', 'Manrope']) {
          await (FontLoader(name)
                ..addFont(rootBundle.load('assets/fonts/$name.ttf')))
              .load();
        }
        var markets = 0;
        final capture = GlobalKey();
        await tester.pumpWidget(ProviderScope(
            overrides: [
              tokenStoreProvider.overrideWithValue(EmptyTokens()),
              assetsProvider.overrideWith((ref) async => []),
              homeSentimentProvider.overrideWith((ref) async => HomeSentiment(
                  value: 64,
                  classification: 'Greed',
                  updatedAt: now,
                  yesterday: 61,
                  lastWeek: 54)),
            ],
            child: MaterialApp(
                theme: PrimeVestDesignSystem.theme,
                home: MediaQuery(
                    data: MediaQueryData(
                        size: size, textScaler: TextScaler.linear(scale)),
                    child: RepaintBoundary(
                        key: capture,
                        child: Scaffold(
                          body: FigmaHomePage(
                              onMarkets: () => markets++,
                              onTrade: () {},
                              onPortfolio: () {},
                              onProfile: () {}),
                          bottomNavigationBar: FigmaHomeNavigation(
                              onSelected: (_) {},
                              labels: const [
                                'Home',
                                'Markets',
                                'Trade',
                                'Portfolio',
                                'Profile'
                              ]),
                        ))))));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Get started'));
        await tester.pumpAndSettle();
        expect(markets, 1);
        await tester.tap(find.byTooltip('Dismiss getting started guide'));
        await tester.pumpAndSettle();
        expect(find.text('Get started'), findsNothing);
        await tester.tap(find.byTooltip('Help and guidance'));
        await tester.pumpAndSettle();
        expect(find.text('How can we help?'), findsOneWidget);
        await tester.tap(find.text('Find an asset'));
        await tester.pumpAndSettle();
        expect(markets, 2);
        await tester.scrollUntilVisible(find.text('View P2P'), 150);
        await tester.pumpAndSettle();
        await tester.tap(find.text('View P2P'));
        await tester.pumpAndSettle();
        expect(find.text('P2P trading'), findsOneWidget);
        expect(tester.takeException(), isNull);
        Navigator.of(tester.element(find.text('P2P trading'))).pop();
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
            find.text('Sign in to see community discussions.'), 180);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (Platform.environment['HOME_SCREENSHOTS'] == '1' &&
            size.width == 402 &&
            scale == 1) {
          final boundary = capture.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
          Future<void> save(String name) async {
            await tester.runAsync(() async {
              final image = await boundary.toImage(pixelRatio: 2);
              final bytes =
                  await image.toByteData(format: ui.ImageByteFormat.png);
              await File('../../artifacts/figma-home-20261106/$name.png')
                  .writeAsBytes(bytes!.buffer.asUint8List());
            });
          }

          await save('home-lower');
          await tester.drag(find.byType(ListView).first, const Offset(0, 2400));
          await tester.pumpAndSettle();
          await save('home-top');
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      });
    }
  }
}
