import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:primevest_mobile/app/terminal_design.dart';
import 'package:primevest_mobile/app/top_notification.dart';
import 'package:primevest_mobile/core/api/api_contract.dart';
import 'package:primevest_mobile/core/app_providers.dart';
import 'package:primevest_mobile/core/trading/contract_display.dart';
import 'package:primevest_mobile/demo/models.dart';
import 'package:primevest_mobile/demo/providers.dart';
import 'package:primevest_mobile/features/shared/market_widgets.dart';

class TerminalPortfolioPage extends ConsumerStatefulWidget {
  const TerminalPortfolioPage({super.key});
  @override
  ConsumerState<TerminalPortfolioPage> createState() =>
      _TerminalPortfolioPageState();
}

class _TerminalPortfolioPageState extends ConsumerState<TerminalPortfolioPage> {
  int tab = 0;
  final closing = <String>{};
  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(selectedAccountModeProvider);
    final auth = ref.watch(sessionProvider).phase == SessionPhase.authenticated;
    final demo = ref.watch(demoAccountProvider);
    final catalogue = ref.watch(assetsProvider).valueOrNull ?? <MarketAsset>[];
    MarketAsset? asset(String id) =>
        catalogue.where((a) => a.id == id).firstOrNull;
    final accounts = ref.watch(accountsProvider);
    final wallet = accounts.valueOrNull
        ?.where((a) => a.mode == mode)
        .firstOrNull
        ?.wallets
        .firstOrNull;
    final positions = ref.watch(positionsProvider(mode));
    final contracts = ref.watch(timedContractsProvider(mode));
    final prices = ref.watch(marketProvider).prices;
    Future<void> close(String id) async {
      if (closing.contains(id)) return;
      setState(() => closing.add(id));
      try {
        if (auth) {
          await ref.read(tradingRepositoryProvider).closePosition(id);
          ref.invalidate(positionsProvider(mode));
          ref.invalidate(accountsProvider);
        } else {
          ref.read(demoAccountProvider.notifier).closePosition(id);
        }
      } catch (e) {
        if (mounted) {
          showTopNotification(
              e is ApiFailure
                  ? e.message
                  : 'Position could not be closed. Please try again.',
              success: false);
        }
      } finally {
        if (mounted) setState(() => closing.remove(id));
      }
    }

    final cards = <Widget>[];
    if (auth) {
      if (tab == 1) {
        for (final c in contracts.valueOrNull ?? []) {
          final pnl = double.tryParse(c.payoutAmount ?? '');
          final stake = double.tryParse(c.investmentAmount);
          cards.add(ActivityCard(
              asset: asset(c.instrumentId),
              title:
                  asset(c.instrumentId)?.symbol ?? c.instrumentId.toUpperCase(),
              badge: '${c.direction} · ${c.result}',
              value: c.result == 'PENDING'
                  ? contractTimeRemaining(c.expiryTimestamp)
                  : 'Returned \$${c.payoutAmount ?? '—'}',
              positive: c.result == 'WIN',
              subtitle:
                  'Stake \$${c.investmentAmount}${pnl != null && stake != null ? ' · P/L \$${(pnl - stake).toStringAsFixed(2)}' : ''} · Fee \$${c.feeAmount ?? '0.00'}'));
        }
      } else {
        for (final p in positions.valueOrNull ?? []) {
          if ((tab == 0 && p.status != 'OPEN') ||
              (tab == 2 && p.status == 'OPEN')) {
            continue;
          }
          final pnl = double.tryParse(
              p.status == 'OPEN' ? p.unrealizedPnl : p.realizedPnl);
          cards.add(ActivityCard(
              asset: asset(p.instrumentId),
              title:
                  asset(p.instrumentId)?.symbol ?? p.instrumentId.toUpperCase(),
              badge: '${p.side} · ${p.status}',
              value: pnl == null ? '—' : '\$${pnl.toStringAsFixed(2)}',
              positive: (pnl ?? 0) >= 0,
              subtitle: 'Entry ${p.averageEntry} · Qty ${p.quantity}',
              action: p.status == 'OPEN'
                  ? TextButton(
                      onPressed:
                          closing.contains(p.id) ? null : () => close(p.id),
                      child:
                          Text(closing.contains(p.id) ? 'Closing…' : 'Close'))
                  : null));
        }
      }
    } else if (tab == 0) {
      for (final p in demo.positions) {
        final a = asset(p.assetId);
        final price = prices[p.assetId] ?? p.entryPrice;
        final pnl = ((price - p.entryPrice) *
                p.quantity *
                100 *
                (p.side == TradeSide.buy ? 1 : -1))
            .round();
        cards.add(ActivityCard(
            asset: a,
            title: a?.symbol ?? p.assetId,
            badge: p.side.name.toUpperCase(),
            value: usdFromCents(pnl),
            positive: pnl >= 0,
            subtitle:
                'Entry ${p.entryPrice.toStringAsFixed(a?.precision ?? 2)} · ${usdFromCents(p.stakePaisa)}',
            action: TextButton(
                onPressed: closing.contains(p.id) ? null : () => close(p.id),
                child: const Text('Close'))));
      }
    } else if (tab == 1) {
      for (final c in demo.contracts) {
        cards.add(ActivityCard(
            asset: asset(c.assetId),
            title: asset(c.assetId)?.symbol ?? c.assetId,
            badge: c.direction.name.toUpperCase(),
            value: c.result == ContractResult.pending
                ? contractTimeRemaining(c.expiryTimestamp)
                : c.result.name.toUpperCase(),
            positive: c.result == ContractResult.win,
            subtitle:
                '${usdFromCents(c.investmentPaisa)} · Virtual price-move settlement'));
      }
    } else {
      for (final r in demo.history) {
        cards.add(ActivityCard(
            asset: asset(r.position.assetId),
            title: asset(r.position.assetId)?.symbol ?? r.position.assetId,
            badge: r.position.side.name.toUpperCase(),
            value: usdFromCents(r.pnlPaisa),
            positive: r.pnlPaisa >= 0,
            subtitle: 'Closed ${timeAgo(r.closedAt)}'));
      }
    }
    final request = tab == 1 ? contracts : positions;
    return RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(accountsProvider);
          ref.invalidate(positionsProvider(mode));
          ref.invalidate(timedContractsProvider(mode));
        },
        child: ListView(padding: EdgeInsets.zero, children: [
          const TerminalHeader(title: 'Portfolio'),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const TerminalBalance(),
                    const SizedBox(height: 15),
                    TerminalPanel(
                        padding: EdgeInsets.zero,
                        child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(children: [
                              for (final (i, title, body) in [
                                (
                                  0,
                                  'Positions',
                                  'Open trades and unrealized P/L'
                                ),
                                (
                                  1,
                                  'Timed contracts',
                                  'Price-move contracts and settlement'
                                ),
                                (
                                  2,
                                  'Trade history',
                                  'Closed positions and returns'
                                )
                              ])
                                InkWell(
                                    onTap: () => setState(() => tab = i),
                                    child: Container(
                                        width: 164,
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                            color: tab == i
                                                ? TerminalDesign.gold
                                                    .withValues(alpha: .08)
                                                : Colors.transparent,
                                            border: const Border(
                                                right: BorderSide(
                                                    color:
                                                        TerminalDesign.edge))),
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text('$title ›',
                                                  style: TextStyle(
                                                      fontFamily: 'Manrope',
                                                      fontSize: 15,
                                                      color: tab == i
                                                          ? TerminalDesign.gold
                                                          : TerminalDesign
                                                              .muted)),
                                              const SizedBox(height: 15),
                                              Text(body,
                                                  style: const TextStyle(
                                                      fontSize: 9,
                                                      color:
                                                          TerminalDesign.muted,
                                                      height: 1.5))
                                            ])))
                            ]))),
                    const SizedBox(height: 15),
                    TerminalPanel(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          const TerminalEyebrow('ASSETS'),
                          const SizedBox(height: 6),
                          Text(
                              [
                                'Open positions',
                                'Timed contracts',
                                'Trade history'
                              ][tab],
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 18),
                          Wrap(spacing: 24, runSpacing: 12, children: [
                            _balance(
                                'Available',
                                auth
                                    ? '\$${wallet?.available ?? '—'}'
                                    : usdFromCents(demo.availablePaisa)),
                            _balance(
                                'Locked',
                                auth
                                    ? '\$${wallet?.locked ?? '—'}'
                                    : usdFromCents(demo.lockedPaisa))
                          ]),
                          const SizedBox(height: 16),
                          const Divider(),
                          const SizedBox(height: 16),
                          if (auth && request.isLoading)
                            const Center(child: CircularProgressIndicator())
                          else if (auth && request.hasError)
                            Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                      'Activity is unavailable. Pull down to retry.',
                                      style: TextStyle(
                                          color: TerminalDesign.muted)),
                                  TextButton(
                                      onPressed: () {
                                        ref.invalidate(positionsProvider(mode));
                                        ref.invalidate(
                                            timedContractsProvider(mode));
                                      },
                                      child: const Text('Retry'))
                                ])
                          else if (cards.isEmpty)
                            Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 20),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                          [
                                            Icons.layers_clear_outlined,
                                            Icons.timer_outlined,
                                            Icons.history
                                          ][tab],
                                          color: TerminalDesign.muted,
                                          size: 30),
                                      const SizedBox(height: 10),
                                      Text(
                                          [
                                            'No open positions',
                                            'No timed contracts',
                                            'No closed trades'
                                          ][tab],
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700)),
                                      const SizedBox(height: 6),
                                      const Text(
                                          'Your trading activity will appear here.',
                                          style: TextStyle(
                                              color: TerminalDesign.muted,
                                              fontSize: 11)),
                                      TextButton(
                                          onPressed: () =>
                                              context.go('/home?tab=2'),
                                          child: const Text('Open terminal →'))
                                    ]))
                          else
                            ...cards,
                        ])),
                    const SizedBox(height: 16),
                    Wrap(spacing: 12, runSpacing: 8, children: [
                      TextButton.icon(
                          onPressed: () =>
                              context.push(auth ? '/cash-in' : '/login'),
                          icon: const Icon(Icons.add, size: 17),
                          label: const Text('Deposit')),
                      TextButton.icon(
                          onPressed: () =>
                              context.push(auth ? '/withdraw' : '/login'),
                          icon: const Icon(Icons.north_east, size: 17),
                          label: const Text('Withdraw')),
                      if (!auth)
                        TextButton.icon(
                            onPressed: () => context.push('/transactions'),
                            icon: const Icon(Icons.receipt_long, size: 17),
                            label: const Text('Balance history'))
                    ]),
                    const SizedBox(height: 24),
                  ])),
        ]));
  }

  Widget _balance(String label, String value) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(fontSize: 10, color: TerminalDesign.muted)),
        Text(value,
            style: const TextStyle(
                fontFamily: 'Manrope',
                fontSize: 16,
                fontWeight: FontWeight.w700))
      ]);
}
