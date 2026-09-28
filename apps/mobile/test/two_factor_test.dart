import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:primevest_mobile/core/api/primevest_api_client.dart';
import 'package:primevest_mobile/core/account/account_repository.dart';
import 'package:primevest_mobile/core/app_providers.dart';
import 'package:primevest_mobile/core/auth/verification_repository.dart';
import 'package:primevest_mobile/features/profile/two_factor_widgets.dart';
import 'api_client_test.dart' show CallbackAdapter, MemoryTokenStore;

const inactive = VerificationStatus(
    emailEnabled: false,
    authenticatorEnabled: false,
    emailAvailable: true,
    authenticatorAvailable: true,
    email: 'test@example.com');
const both = VerificationStatus(
    emailEnabled: true,
    authenticatorEnabled: true,
    emailAvailable: true,
    authenticatorAvailable: true,
    email: 'test@example.com');
void main() {
  test(
      'reset demo uses the authenticated server endpoint and supplied request key',
      () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test.invalid'));
    dio.httpClientAdapter = CallbackAdapter((options) async {
      expect(options.path, '/accounts/demo/reset');
      expect(options.headers['Idempotency-Key'], 'reset:test');
      expect(options.data, isEmpty);
      return ResponseBody.fromString(
          jsonEncode({
            'data': {'available': '1000.00'},
            'meta': {'requestId': 'test', 'timestamp': '2026-09-28T00:00:00Z'}
          }),
          200,
          headers: {
            Headers.contentTypeHeader: ['application/json']
          });
    });
    final repository = AccountRepository(PrimeVestApiClient(
        tokenStore: MemoryTokenStore(), dio: dio, refreshDio: dio));
    expect((await repository.resetDemo('reset:test'))['available'], '1000.00');
  });
  testWidgets(
      'top prompt is visible without factors and disappears when enabled',
      (tester) async {
    await tester.pumpWidget(ProviderScope(overrides: [
      verificationStatusProvider.overrideWith((ref) async => inactive)
    ], child: const MaterialApp(home: Scaffold(body: TwoFactorPrompt()))));
    await tester.pumpAndSettle();
    expect(find.text('Set up'), findsOneWidget);
    await tester.pumpWidget(ProviderScope(
        key: const ValueKey('enabled'),
        overrides: [
          verificationStatusProvider.overrideWith((ref) async => both)
        ],
        child: const MaterialApp(home: Scaffold(body: TwoFactorPrompt()))));
    await tester.pumpAndSettle();
    expect(find.text('Set up'), findsNothing);
  });
  testWidgets('security settings display both independently enrolled methods',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
        overrides: [
          verificationStatusProvider.overrideWith((ref) async => both)
        ],
        child: const MaterialApp(
            home: Scaffold(
                body: SingleChildScrollView(child: TwoFactorSettings())))));
    await tester.pumpAndSettle();
    expect(find.text('Email OTP'), findsOneWidget);
    expect(find.text('Authenticator app'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsNWidgets(2));
    expect(find.text('Enable'), findsNothing);
  });
  testWidgets('withdrawal can choose an enabled method and requires six digits',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(
            home: Scaffold(body: WithdrawalFactorDialog(status: both)))));
    expect(find.text('Authenticator'), findsOneWidget);
    await tester.tap(find.text('Submit withdrawal'));
    await tester.pump();
    expect(find.text('Send and enter a valid 6-digit code.'), findsOneWidget);
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Email OTP').last);
    await tester.pumpAndSettle();
    expect(find.text('Send code'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
