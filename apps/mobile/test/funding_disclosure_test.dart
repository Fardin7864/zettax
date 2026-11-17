import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:primevest_mobile/core/app_providers.dart';
import 'package:primevest_mobile/core/funding/funding_models.dart';
import 'package:primevest_mobile/features/funding/funding_screens.dart';
import 'funding_tabs_test.dart' show HistoryRepository;

void main() {
  testWidgets(
      'active virtual funding discloses the recipient and requires revocable consent',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(overrides: [
      fundingRepositoryProvider.overrideWithValue(HistoryRepository()),
      depositMethodsProvider.overrideWith((ref) async => const FundingMethods(
            submissionsEnabled: true,
            virtualFunding: true,
            methods: [
              FundingMethod(
                  id: 'method',
                  type: 'MANUAL',
                  displayName: 'Practice request',
                  accountNumber: 'private-receiving-number',
                  accountType: 'VIRTUAL',
                  instructions: 'No money is transferred.',
                  minimum: '1',
                  maximum: '1000')
            ],
          )),
    ], child: const MaterialApp(home: CashInScreen())));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'Virtual funding is active. Submit the amount and reference for admin review; no real money is transferred.'),
        findsOneWidget);
    expect(find.textContaining('api.zettax.app'), findsOneWidget);
    expect(find.text('private-receiving-number'), findsNothing);
    expect(find.text('Fictional practice number'), findsOneWidget);
    expect(find.textContaining('Never enter a payment-service password'),
        findsOneWidget);
    final submit = find.ancestor(
        of: find.text('Submit practice request'),
        matching: find.byType(FilledButton));
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });
}
