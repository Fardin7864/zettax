import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:primevest_mobile/app/design_system.dart';
import 'package:primevest_mobile/demo/providers.dart';
import 'package:primevest_mobile/features/shared/market_widgets.dart';

class DemoTransactionsScreen extends ConsumerWidget {
  const DemoTransactionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactions = ref.watch(demoAccountProvider).transactions;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Demo transactions'),
        actions: const [DemoBadge(), SizedBox(width: 12)],
      ),
      body: transactions.isEmpty
          ? const EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No transactions yet',
              body: 'Your virtual balance activity will appear here.')
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
              itemCount: transactions.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, index) {
                final item = transactions[index];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 5),
                  leading: CircleAvatar(
                    backgroundColor: item.amountPaisa >= 0
                        ? PrimeVestDesignSystem.positive.withValues(alpha: .13)
                        : PrimeVestDesignSystem.primaryGold
                            .withValues(alpha: .13),
                    child: Icon(
                      item.amountPaisa >= 0
                          ? Icons.south_west
                          : Icons.north_east,
                      color: item.amountPaisa >= 0
                          ? PrimeVestDesignSystem.positive
                          : PrimeVestDesignSystem.primaryGold,
                    ),
                  ),
                  title: Text(item.title,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${item.id} • ${timeAgo(item.createdAt)}'),
                  trailing: Text(
                    bdt(item.amountPaisa),
                    style: TextStyle(
                      color: item.amountPaisa >= 0
                          ? PrimeVestDesignSystem.positive
                          : PrimeVestDesignSystem.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                );
              },
            ),
    );
  }
}
