import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:primevest_mobile/app/design_system.dart';
import 'package:primevest_mobile/core/account/account_models.dart';
import 'package:primevest_mobile/core/app_providers.dart';

class AccountModeSelector extends ConsumerWidget {
  const AccountModeSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(selectedAccountModeProvider);
    final config = ref.watch(systemConfigProvider).valueOrNull ??
        PublicSystemConfig.failClosed;
    return PopupMenuButton<AccountMode>(
      tooltip: 'Switch account mode',
      initialValue: mode,
      onSelected: (selected) {
        ref.read(selectedAccountModeProvider.notifier).state = selected;
        ref.invalidate(accountsProvider);
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: AccountMode.demo,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.school_outlined),
            title: Text('DEMO'),
            subtitle: Text('Virtual funds'),
          ),
        ),
        PopupMenuItem(
          value: AccountMode.real,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.account_balance_outlined),
            title: const Text('REAL'),
            subtitle: Text(config.usesVirtualFunds
                ? 'Virtual balance'
                : config.realTrading
                    ? 'Availability set by Zettax'
                    : 'Trading unavailable'),
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: mode == AccountMode.demo
              ? const Color(0x28F8B425)
              : const Color(0x2238BDF8),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: mode == AccountMode.demo
                ? PrimeVestDesignSystem.primaryGold
                : const Color(0xFF38BDF8),
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(
            mode.apiValue,
            style: TextStyle(
              color: mode == AccountMode.demo
                  ? PrimeVestDesignSystem.primaryGold
                  : const Color(0xFF7DD3FC),
              fontWeight: FontWeight.w900,
              fontSize: 10,
              letterSpacing: .8,
            ),
          ),
          const SizedBox(width: 3),
          const Icon(Icons.expand_more, size: 14),
        ]),
      ),
    );
  }
}

class RealUnavailableCard extends ConsumerWidget {
  const RealUnavailableCard({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(systemConfigProvider).valueOrNull ??
        PublicSystemConfig.failClosed;
    return Container(
      padding: EdgeInsets.all(compact ? 16 : 22),
      decoration: BoxDecoration(
        color: PrimeVestDesignSystem.surfaceDark,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x3348BDF8)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.lock_outline, color: Color(0xFF7DD3FC)),
          SizedBox(width: 10),
          Text('Account services',
              style: TextStyle(fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 9),
        Text(
          '${config.usesVirtualFunds ? 'Virtual account' : 'Account services'}\n'
          'Deposit: ${config.realDeposits ? 'available' : 'not available yet'}\n'
          'Withdraw: ${config.realWithdrawals ? 'available' : 'not available yet'}\n'
          'Trading: ${config.realTrading ? 'available' : 'not available yet'}',
          style: const TextStyle(
            color: PrimeVestDesignSystem.textMuted,
            fontSize: 12,
            height: 1.4,
          ),
        ),
      ]),
    );
  }
}
