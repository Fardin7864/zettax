import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:primevest_mobile/core/api/api_contract.dart';
import 'package:primevest_mobile/core/api/primevest_api_client.dart';
import 'package:primevest_mobile/core/app_providers.dart';
import 'package:primevest_mobile/core/funding/funding_models.dart';
import 'package:primevest_mobile/core/funding/funding_repository.dart';
import 'package:primevest_mobile/features/funding/funding_screens.dart';
import 'api_client_test.dart' show MemoryTokenStore;

class HistoryRepository extends FundingRepository {
  HistoryRepository()
      : super(PrimeVestApiClient(tokenStore: MemoryTokenStore()));
  String status = 'PENDING_REVIEW';
  int calls = 0;
  @override
  Future<List<JsonObject>> history(String path) async {
    calls++;
    return [
      {'amount': '100.00', 'status': status, 'updatedAt': '2026-09-18'}
    ];
  }
}

void main() {
  for (final withdrawal in [false, true]) {
    testWidgets(
        '${withdrawal ? 'Withdrawal' : 'Deposit'} tabs show live history status',
        (tester) async {
      final repository = HistoryRepository();
      final container = ProviderContainer(overrides: [
        fundingRepositoryProvider.overrideWithValue(repository),
        depositMethodsProvider.overrideWith((ref) async => const FundingMethods(
            submissionsEnabled: true, methods: [], virtualFunding: true)),
        withdrawalMethodsProvider.overrideWith((ref) async =>
            const FundingMethods(
                submissionsEnabled: true, methods: [], virtualFunding: true)),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
              home:
                  withdrawal ? const WithdrawScreen() : const CashInScreen())));
      await tester.pumpAndSettle();
      expect(find.text('Request'), findsOneWidget);
      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();
      expect(find.text('৳100.00 · PENDING_REVIEW'), findsOneWidget);
      repository.status = withdrawal ? 'PAID' : 'CREDITED';
      container.read(fundingRealtimeRevisionProvider.notifier).state++;
      await tester.pumpAndSettle();
      expect(find.text('৳100.00 · ${repository.status}'), findsOneWidget);
      expect(find.text('৳100.00 · PENDING_REVIEW'), findsNothing);
      expect(repository.calls, greaterThan(1));
    });
  }
}
