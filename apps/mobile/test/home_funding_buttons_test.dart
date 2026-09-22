import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:primevest_mobile/app/design_system.dart';
import 'package:primevest_mobile/core/account/account_models.dart';
import 'package:primevest_mobile/core/app_providers.dart';
import 'package:primevest_mobile/features/home/home_screen.dart';

void main() {
  testWidgets('home Deposit and Withdraw buttons have equal dimensions',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
        overrides: [
          systemConfigProvider
              .overrideWith((ref) async => PublicSystemConfig.failClosed),
        ],
        child: MaterialApp(
            theme: PrimeVestDesignSystem.theme,
            home: const Scaffold(
                body: RealBalanceCard(wallet: null, authenticated: true)))));
    await tester.pumpAndSettle();
    final deposit = find.ancestor(
        of: find.text('Deposit'),
        matching: find.byWidgetPredicate((widget) => widget is FilledButton));
    final withdraw = find.ancestor(
        of: find.text('Withdraw'),
        matching: find.byWidgetPredicate((widget) => widget is OutlinedButton));
    expect(tester.getSize(deposit), tester.getSize(withdraw));
    expect(tester.getSize(deposit).height,
        greaterThanOrEqualTo(PrimeVestDesignSystem.buttonHeight));
  });
}
