import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:primevest_mobile/app/brand_logo.dart';
import 'package:primevest_mobile/core/app_providers.dart';
import 'package:primevest_mobile/core/auth/auth_models.dart';
import 'package:primevest_mobile/core/auth/token_store.dart';
import 'package:primevest_mobile/features/home/home_screen.dart';
import 'package:primevest_mobile/l10n/app_localizations.dart';
import 'package:primevest_mobile/main.dart';
import 'package:primevest_mobile/market/market_data_providers.dart';
import 'package:primevest_mobile/market/market_realtime_client.dart'
    as realtime;

class _EmptyTokenStore implements TokenStore {
  @override
  Future<void> clearTokens() async {}
  @override
  Future<DeviceMetadata> deviceMetadata() async => const DeviceMetadata(
        deviceFingerprint: 'widget-test-device-fingerprint',
        deviceName: 'Widget test',
        devicePlatform: 'test',
      );
  @override
  Future<SessionTokens?> readTokens() async => null;
  @override
  Future<void> writeTokens(SessionTokens tokens) async {}
}

class _DelayedTokenStore extends _EmptyTokenStore {
  final Completer<SessionTokens?> restored = Completer<SessionTokens?>();

  @override
  Future<SessionTokens?> readTokens() => restored.future;
}

class _NoopMarketRealtimeClient extends realtime.MarketRealtimeClient {
  _NoopMarketRealtimeClient() : super(tokenStore: _EmptyTokenStore());

  @override
  Future<realtime.MarketRealtimeSubscription?> subscribe({
    required String instrumentId,
    required String interval,
    required void Function(realtime.MarketRealtimeUpdate update) onCandle,
    required void Function() onSequenceGap,
    required void Function(bool connected) onConnectionChanged,
  }) async =>
      null;
}

Widget _app({TokenStore? tokenStore}) => ProviderScope(
      overrides: [
        tokenStoreProvider.overrideWithValue(tokenStore ?? _EmptyTokenStore()),
        marketRealtimeClientProvider
            .overrideWithValue(_NoopMarketRealtimeClient()),
      ],
      child: const PrimeVestApp(),
    );

Widget _home(int tab, Key key) => ProviderScope(
      overrides: [
        marketRealtimeClientProvider
            .overrideWithValue(_NoopMarketRealtimeClient()),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: HomeScreen(key: key, initialTab: tab),
      ),
    );

Future<void> _leaveSplash(WidgetTester tester) async {
  await tester.pump(); // Complete the token-store bootstrap and rebuild router.
  await tester.pump(const Duration(milliseconds: 800));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows Zettax brand on launch', (tester) async {
    await tester.pumpWidget(_app());
    expect(find.byType(ZettaxWordmark), findsOneWidget);
    await _leaveSplash(tester);
    expect(find.text('Try Demo'), findsOneWidget);
    expect(find.byType(ZettaxMark), findsOneWidget);
  });

  testWidgets('leaves splash when session restoration finishes late',
      (tester) async {
    final tokenStore = _DelayedTokenStore();
    await tester.pumpWidget(_app(tokenStore: tokenStore));
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(ZettaxWordmark), findsOneWidget);

    tokenStore.restored.complete(null);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Try Demo'), findsOneWidget);
  });

  testWidgets('hamburger menu opens the community screen for guests',
      (tester) async {
    await tester.pumpWidget(_app());
    await _leaveSplash(tester);
    await tester.tap(find.text('Try Demo'));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsNothing);
    await tester.tap(find.byTooltip('Open menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Community').last);
    await tester.pumpAndSettle();

    expect(find.text('Sign in to join the community'), findsOneWidget);
    expect(find.text('Create post'), findsOneWidget);
    await tester.tap(find.text('Create post'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);
  });

  testWidgets('community post action fits a narrow phone app bar',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_home(5, const ValueKey('narrow-community')));
    await tester.pump();

    expect(find.text('Post'), findsOneWidget);
    expect(find.text('Latest posts'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('registration asks only for email and password', (tester) async {
    await tester.pumpWidget(_app());
    await _leaveSplash(tester);

    await tester.tap(find.text('Create Account'));
    await tester.pumpAndSettle();
    expect(find.text('Create your account'), findsOneWidget);
    expect(find.text('Email address'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Continue with Google'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Full name'), findsNothing);
    expect(find.text('Mobile number'), findsNothing);

    final container =
        ProviderScope.containerOf(tester.element(find.byType(PrimeVestApp)));
    container.read(routerProvider).go('/login');
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Forgot password?'), findsOneWidget);
  });

  testWidgets('home route updates the selected tab when query tab changes',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const key = ValueKey('home-route');
    await tester.pumpWidget(_home(0, key));
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byTooltip('Open menu'), findsOneWidget);
    await tester.tap(find.byTooltip('Open menu'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Community'), findsWidgets);
    await tester.tapAt(const Offset(800, 100));
    await tester.pump(const Duration(milliseconds: 350));

    await tester.pumpWidget(_home(2, key));
    await tester.pump();

    expect(find.byType(NavigationBar), findsNothing);
    // The test has no market catalogue, so TradePage is showing its loader.
    // Invoke the back action provided by HomeScreen to test the tab return.
    tester.widget<TradePage>(find.byType(TradePage)).onBack();
    await tester.pump();
    expect(find.byType(NavigationBar), findsNothing);

    await tester.pumpWidget(_home(1, key));
    await tester.pumpWidget(_home(2, key));
    await tester.pump();
    tester.widget<TradePage>(find.byType(TradePage)).onBack();
    await tester.pump();
    expect(find.byType(NavigationBar), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 300));
  });
}
