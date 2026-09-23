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

Widget _app() => ProviderScope(
      overrides: [tokenStoreProvider.overrideWithValue(_EmptyTokenStore())],
      child: const PrimeVestApp(),
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

  testWidgets('registration asks only for email and password', (tester) async {
    await tester.pumpWidget(_app());
    await _leaveSplash(tester);

    await tester.tap(find.text('Create Account'));
    await tester.pumpAndSettle();
    expect(find.text('Create your account'), findsOneWidget);
    expect(find.text('Email address'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
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
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: HomeScreen(key: key, initialTab: 0),
        ),
      ),
    );
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
    );

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: HomeScreen(key: key, initialTab: 2),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(NavigationBar), findsNothing);
    // The test has no market catalogue, so TradePage is showing its loader.
    // Invoke the back action provided by HomeScreen to test the tab return.
    tester.widget<TradePage>(find.byType(TradePage)).onBack();
    await tester.pump();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
    );

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: HomeScreen(key: key, initialTab: 1),
        ),
      ),
    );
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: HomeScreen(key: key, initialTab: 2),
        ),
      ),
    );
    await tester.pump();
    tester.widget<TradePage>(find.byType(TradePage)).onBack();
    await tester.pump();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 300));
  });
}
