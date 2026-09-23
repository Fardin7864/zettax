import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:primevest_mobile/app/design_system.dart';
import 'package:primevest_mobile/app/app_update_host.dart';
import 'package:primevest_mobile/app/top_notification.dart';
import 'package:primevest_mobile/core/app_providers.dart';
import 'package:primevest_mobile/features/asset/asset_detail_screen.dart';
import 'package:primevest_mobile/features/auth/auth_screen.dart';
import 'package:primevest_mobile/features/home/home_screen.dart';
import 'package:primevest_mobile/features/funding/funding_screens.dart';
import 'package:primevest_mobile/features/onboarding/welcome_screen.dart';
import 'package:primevest_mobile/features/portfolio/demo_transactions_screen.dart';
import 'package:primevest_mobile/features/profile/education_screen.dart';
import 'package:primevest_mobile/features/profile/language_screen.dart';
import 'package:primevest_mobile/features/profile/security_screen.dart';
import 'package:primevest_mobile/features/splash/splash_screen.dart';
import 'package:primevest_mobile/l10n/app_localizations.dart';
import 'package:primevest_mobile/app/web_url_strategy_stub.dart'
    if (dart.library.js_interop) 'package:primevest_mobile/app/web_url_strategy.dart';

void main() {
  configureWebUrlStrategy();
  runApp(const ProviderScope(child: PrimeVestApp()));
}

final rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
final rootNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final session = ref.watch(sessionProvider);
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: kIsWeb ? '/' : '/splash',
    redirect: (_, state) {
      final location = state.matchedLocation;
      if (session.phase == SessionPhase.bootstrapping) {
        if (kIsWeb && location != '/' && location != '/splash') return null;
        return location == '/splash' ? null : '/splash';
      }
      if (location == '/') {
        return kIsWeb
            ? '/home?tab=2'
            : session.phase == SessionPhase.authenticated
                ? '/home'
                : '/welcome';
      }
      if (session.phase == SessionPhase.authenticated &&
          (location == '/splash' ||
              location == '/welcome' ||
              location == '/login' ||
              location == '/register')) {
        return kIsWeb ? '/home?tab=2' : '/home';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/welcome', builder: (_, __) => const WelcomeScreen()),
      GoRoute(
          path: '/login',
          builder: (_, __) => const AuthScreen(mode: AuthMode.login)),
      GoRoute(
          path: '/register',
          builder: (_, __) => const AuthScreen(mode: AuthMode.register)),
      GoRoute(
          path: '/forgot-password',
          builder: (_, __) => const AuthScreen(mode: AuthMode.forgotPassword)),
      GoRoute(
        path: '/home',
        builder: (_, state) => HomeScreen(
          initialTab: int.tryParse(state.uri.queryParameters['tab'] ?? '') ?? 0,
        ),
      ),
      GoRoute(
        path: '/asset/:id',
        builder: (_, state) =>
            AssetDetailScreen(assetId: state.pathParameters['id']!),
      ),
      GoRoute(
          path: '/transactions',
          builder: (_, __) => const DemoTransactionsScreen()),
      GoRoute(path: '/cash-in', builder: (_, __) => const CashInScreen()),
      GoRoute(path: '/withdraw', builder: (_, __) => const WithdrawScreen()),
      GoRoute(path: '/security', builder: (_, __) => const SecurityScreen()),
      GoRoute(path: '/language', builder: (_, __) => const LanguageScreen()),
      GoRoute(path: '/education', builder: (_, __) => const EducationScreen()),
      GoRoute(path: '/risk', builder: (_, __) => const RiskDisclosureScreen()),
    ],
  );
});

class PrimeVestApp extends ConsumerWidget {
  const PrimeVestApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(accountRealtimeBridgeProvider);
    ref.listen<FundingRealtimeNotice?>(fundingRealtimeNoticeProvider,
        (previous, next) {
      if (next == null || next.id == previous?.id) return;
      showTopNotification(next.message);
    });
    return MaterialApp.router(
      title: 'Zettax',
      debugShowCheckedModeBanner: false,
      theme: PrimeVestDesignSystem.theme,
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      builder: (context, child) {
        final content =
            TopNotificationHost(child: child ?? const SizedBox.shrink());
        if (kIsWeb) {
          return ColoredBox(
            color: PrimeVestDesignSystem.backgroundDark,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1900),
                child: content,
              ),
            ),
          );
        }
        return AppUpdateHost(navigatorKey: rootNavigatorKey, child: content);
      },
      routerConfig: ref.watch(routerProvider),
      locale: ref.watch(appLocaleProvider),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
    );
  }
}
