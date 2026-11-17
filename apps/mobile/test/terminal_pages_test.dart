import 'package:primevest_mobile/core/auth/auth_models.dart';
import 'package:primevest_mobile/features/community/community_screen.dart';
import 'home_community_data_test.dart' show FeedClient;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:primevest_mobile/app/design_system.dart';
import 'package:primevest_mobile/app/terminal_design.dart';
import 'package:primevest_mobile/core/app_providers.dart';
import 'package:primevest_mobile/demo/models.dart';
import 'package:primevest_mobile/demo/providers.dart';
import 'package:primevest_mobile/features/home/home_screen.dart';
import 'package:primevest_mobile/features/terminal/terminal_markets.dart';
import 'package:primevest_mobile/features/terminal/terminal_portfolio.dart';
import 'package:primevest_mobile/market/market_data_api.dart';
import 'package:primevest_mobile/market/market_data_providers.dart';
import 'package:primevest_mobile/market/market_realtime_client.dart';
import 'figma_home_test.dart' show EmptyTokens;

const fixtures = [
  MarketAsset(
      id: 'btc-usd',
      symbol: 'BTC/USD',
      name: 'Bitcoin',
      assetClass: 'Crypto',
      price: 100,
      changePercent: 0,
      precision: 2),
  MarketAsset(
      id: 'eth-usd',
      symbol: 'ETH/USD',
      name: 'Ethereum',
      assetClass: 'Crypto',
      price: 100,
      changePercent: 0,
      precision: 2),
  MarketAsset(
      id: 'eur-usd',
      symbol: 'EUR/USD',
      name: 'Euro / Dollar',
      assetClass: 'Forex',
      price: 1,
      changePercent: 0,
      precision: 4)
];

class ObservedMarket extends MarketDataApi {
  @override
  Future<MarketCandleSeries> fetchCandles(String instrumentId, String interval,
      {int limit = 90, DateTime? before}) async {
    final now = DateTime.utc(2026, 11, 6, 8);
    return MarketCandleSeries(
        instrumentId: instrumentId,
        symbol: 'BTC/USD',
        providerId: 'fixture',
        provider: 'Test observations',
        sourceSymbol: 'BTCUSDT',
        freshness: 'LIVE',
        requestedInterval: interval,
        effectiveInterval: interval,
        providerTimestamp: now,
        executionPrice: false,
        executionEligible: false,
        isSyntheticOhlc: false,
        receivedAt: DateTime.now().toUtc(),
        nextCursor: null,
        candles: List.generate(
            120,
            (i) => MarketCandle(
                openTime: now.subtract(Duration(minutes: 120 - i)),
                closeTime: now.subtract(Duration(minutes: 119 - i)),
                open: 100 + i.toDouble(),
                high: 102 + i.toDouble(),
                low: 99 + i.toDouble(),
                close: 101 + i.toDouble(),
                volume: 20)),
        delivery: 'REST');
  }
}

class QuietRealtime extends MarketRealtimeClient {
  QuietRealtime() : super(tokenStore: EmptyTokens());
  @override
  Future<MarketRealtimeSubscription?> subscribe(
          {required String instrumentId,
          required String interval,
          required void Function(MarketRealtimeUpdate update) onCandle,
          required void Function() onSequenceGap,
          required void Function(bool connected) onConnectionChanged}) async =>
      null;
}

Widget harness(Widget page, Size size, double scale) => ProviderScope(
        overrides: [
          tokenStoreProvider.overrideWithValue(EmptyTokens()),
          assetsProvider.overrideWith((ref) async => fixtures),
          marketDataApiProvider.overrideWithValue(ObservedMarket()),
          marketRealtimeClientProvider.overrideWithValue(QuietRealtime()),
        ],
        child: MaterialApp(
            theme: TerminalDesign.theme(PrimeVestDesignSystem.theme),
            home: MediaQuery(
                data: MediaQueryData(
                    size: size, textScaler: TextScaler.linear(scale)),
                child: DecoratedBox(
                    decoration: const BoxDecoration(
                        gradient: TerminalDesign.background),
                    child: Scaffold(body: page)))));

class StaticSession extends StateNotifier<SessionState>
    implements SessionController {
  StaticSession(super.state);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('authenticated community keeps composer and the first real post',
      (tester) async {
    tester.view.physicalSize = const Size(640, 1440);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = FeedClient();
    await tester.pumpWidget(ProviderScope(
        overrides: [
          tokenStoreProvider.overrideWithValue(EmptyTokens()),
          sessionProvider.overrideWith((ref) => StaticSession(
              const SessionState.authenticated(
                  AuthUser(id: 'test-user', email: 'user@example.com')))),
          apiClientProvider.overrideWithValue(client),
        ],
        child: MaterialApp(
            theme: TerminalDesign.theme(PrimeVestDesignSystem.theme),
            home: const MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(2)),
                child: CommunityScreen(connectRealtime: false)))));
    client.requests.single.complete({
      'items': [
        {
          'id': 'real-post',
          'author': 'Actual member',
          'text': 'Observed market discussion',
          'likeCount': 123,
          'dislikeCount': 2,
          'commentCount': 4,
          'shareCount': 1,
          'myReaction': 'NONE',
          'createdAt': '2026-11-06T08:00:00Z'
        }
      ],
      'nextCursor': null
    });
    await tester.pumpAndSettle();
    expect(find.text('Post'), findsOneWidget);
    await tester.scrollUntilVisible(
        find.text('Observed market discussion'), 150,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Actual member'), findsOneWidget);
    expect(find.text('123'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  for (final size in [const Size(360, 791), const Size(320, 720)]) {
    for (final scale in [1.0, 2.0]) {
      for (final page in ['Markets', 'Portfolio', 'Profile', 'Trade']) {
        testWidgets('$page fits ${size.width} at $scale text', (tester) async {
          tester.view.physicalSize = size * 2;
          tester.view.devicePixelRatio = 2;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          for (final name in ['Manrope', 'DMSans']) {
            await (FontLoader(name)
                  ..addFont(rootBundle.load('assets/fonts/$name.ttf')))
                .load();
          }
          await tester.pumpWidget(harness(
              switch (page) {
                'Markets' => TerminalMarketsPage(onTrade: () {}),
                'Portfolio' => const TerminalPortfolioPage(),
                'Profile' => const ProfilePage(),
                _ => TradePage(onBack: () {})
              },
              size,
              scale));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          if (page == 'Markets') {
            await tester.scrollUntilVisible(find.byType(TextField), 150,
                scrollable: find.byType(Scrollable).first);
            await tester.enterText(find.byType(TextField), 'NO-MATCH');
            await tester.pumpAndSettle();
            expect(find.text('No matching assets.'), findsOneWidget);
            expect(tester.takeException(), isNull);
          } else if (page == 'Portfolio') {
            await tester.tap(find.text('Timed contracts ›'));
            await tester.pumpAndSettle();
            await tester.scrollUntilVisible(
                find.text('No timed contracts'), 150,
                scrollable: find.byType(Scrollable).first);
            expect(find.text('No timed contracts'), findsOneWidget);
          } else if (page == 'Profile') {
            await tester.scrollUntilVisible(find.text('Community'), 150,
                scrollable: find.byType(Scrollable).first);
            expect(find.text('Community'), findsOneWidget);
          } else {
            await tester.scrollUntilVisible(
                find.byKey(const ValueKey('trade-mode-selector')), 250,
                scrollable: find.byType(Scrollable).first);
            await tester.pumpAndSettle();
            await tester.tap(find.text('No expiry'));
            await tester.pumpAndSettle();
            expect(find.byKey(const ValueKey('trade-duration-control')),
                findsNothing);
            await tester.scrollUntilVisible(
                find.byKey(const ValueKey('trade-buy-button')), 150,
                scrollable: find.byType(Scrollable).first);
            expect(find.text('BUY'), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
        });
      }
    }
  }
}
