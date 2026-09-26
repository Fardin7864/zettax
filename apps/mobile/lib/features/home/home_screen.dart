import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:primevest_mobile/app/brand_logo.dart';
import 'package:primevest_mobile/app/design_system.dart';
import 'package:primevest_mobile/app/top_notification.dart';
import 'package:primevest_mobile/features/profile/edit_profile_screen.dart';
import 'package:primevest_mobile/core/account/account_mode_selector.dart';
import 'package:primevest_mobile/core/account/account_models.dart';
import 'package:primevest_mobile/core/app_providers.dart';
import 'package:primevest_mobile/core/api/api_contract.dart';
import 'package:primevest_mobile/core/trading/contract_display.dart';
import 'package:primevest_mobile/demo/models.dart';
import 'package:primevest_mobile/demo/providers.dart';
import 'package:primevest_mobile/features/shared/market_widgets.dart';
import 'package:primevest_mobile/features/shared/ohlc_chart.dart';
import 'package:primevest_mobile/features/shared/live_trade_chart.dart';
import 'package:primevest_mobile/features/shared/market_performance.dart';
import 'package:primevest_mobile/l10n/app_localizations.dart';
import 'package:primevest_mobile/market/display_currency.dart';
import 'package:primevest_mobile/market/market_data_providers.dart';

final selectedAssetProvider = StateProvider<String>((ref) => 'btc-usd');

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late int index = widget.initialTab.clamp(0, 4);
  late int lastNonTradeIndex = index == 2 ? 0 : index;

  void _selectTab(int value) {
    if (value != 2) lastNonTradeIndex = value;
    setState(() => index = value);
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab != widget.initialTab) {
      index = widget.initialTab.clamp(0, 4);
      if (index != 2) lastNonTradeIndex = index;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(accountRealtimeBridgeProvider);
    final l10n = AppLocalizations.of(context);
    final pages = [
      DashboardPage(
          onTrade: () => _selectTab(2), onMarkets: () => _selectTab(1)),
      MarketsPage(onTrade: () => _selectTab(2)),
      TickerMode(
          enabled: index == 2,
          child: TradePage(onBack: () => _selectTab(lastNonTradeIndex))),
      const PortfolioPage(),
      const ProfilePage(),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final wide = kIsWeb && constraints.maxWidth >= 900;
      final content = IndexedStack(index: index, children: pages);
      return Scaffold(
        body: wide
            ? Column(children: [
                _WebNavigationBar(
                  selectedIndex: index,
                  onSelected: _selectTab,
                  labels: [
                    l10n.home,
                    l10n.markets,
                    l10n.trade,
                    l10n.portfolio,
                    l10n.profile,
                  ],
                ),
                Expanded(child: content),
              ])
            : content,
        bottomNavigationBar: index == 2 || wide
            ? null
            : NavigationBar(
                selectedIndex: index,
                onDestinationSelected: _selectTab,
                destinations: [
                  NavigationDestination(
                      icon: const Icon(Icons.home_outlined),
                      selectedIcon: const Icon(Icons.home),
                      label: l10n.home),
                  NavigationDestination(
                      icon: const Icon(Icons.candlestick_chart_outlined),
                      label: l10n.markets),
                  NavigationDestination(
                      icon: const Icon(Icons.swap_vert_circle_outlined),
                      selectedIcon: const Icon(Icons.swap_vert_circle),
                      label: l10n.trade),
                  NavigationDestination(
                      icon: const Icon(Icons.pie_chart_outline),
                      label: l10n.portfolio),
                  NavigationDestination(
                      icon: const Icon(Icons.person_outline),
                      label: l10n.profile),
                ],
              ),
      );
    });
  }
}

class _WebNavigationBar extends ConsumerWidget {
  const _WebNavigationBar({
    required this.selectedIndex,
    required this.onSelected,
    required this.labels,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<String> labels;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final icons = [
      Icons.home_outlined,
      Icons.candlestick_chart_outlined,
      Icons.swap_vert_circle_outlined,
      Icons.pie_chart_outline,
      Icons.person_outline,
    ];
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      decoration: const BoxDecoration(
        color: PrimeVestDesignSystem.surfaceDark,
        border: Border(bottom: BorderSide(color: Color(0xFF40382F))),
      ),
      child: Row(children: [
        const ZettaxMark(height: 34),
        const SizedBox(width: 12),
        const Text('Zettax',
            style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
        const SizedBox(width: 34),
        for (var i = 0; i < labels.length; i++)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: TextButton.icon(
              onPressed: () => onSelected(i),
              icon: Icon(icons[i], size: 19),
              label: Text(labels[i]),
              style: TextButton.styleFrom(
                foregroundColor: i == selectedIndex
                    ? PrimeVestDesignSystem.primaryGold
                    : PrimeVestDesignSystem.textMuted,
                backgroundColor: i == selectedIndex
                    ? const Color(0x333D3324)
                    : Colors.transparent,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        const Spacer(),
        if (session.phase == SessionPhase.authenticated)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(session.user?.email ?? 'Account',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: PrimeVestDesignSystem.textMuted)),
          )
        else
          OutlinedButton(
            onPressed: () => context.push('/login'),
            child: const Text('Sign in'),
          ),
      ]),
    );
  }
}

class PrimeVestHeader extends ConsumerWidget {
  const PrimeVestHeader(
      {super.key, required this.title, this.subtitle, this.actions});
  final String title;
  final String? subtitle;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 10),
          child: Row(children: [
            const ZettaxMark(height: 38),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 19, fontWeight: FontWeight.w800)),
                  if (subtitle != null)
                    Text(subtitle!,
                        style: const TextStyle(
                            color: PrimeVestDesignSystem.textMuted,
                            fontSize: 11)),
                ])),
            ...?actions,
            const AccountModeSelector(),
          ]),
        ),
      );
}

class DashboardPage extends ConsumerWidget {
  const DashboardPage(
      {super.key, required this.onTrade, required this.onMarkets});
  final VoidCallback onTrade;
  final VoidCallback onMarkets;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(demoAccountProvider);
    final mode = ref.watch(selectedAccountModeProvider);
    final authenticated =
        ref.watch(sessionProvider).phase == SessionPhase.authenticated;
    final serverAccount = ref
        .watch(accountsProvider)
        .value
        ?.where((item) => item.mode == mode)
        .firstOrNull;
    final serverWallet = serverAccount?.wallets.firstOrNull;
    final assets = ref.watch(assetsProvider).value ?? const <MarketAsset>[];
    final market = ref.watch(marketProvider);
    if (kIsWeb && MediaQuery.sizeOf(context).width >= 900) {
      final balance = mode == AccountMode.demo
          ? authenticated
              ? ServerBalanceCard(wallet: serverWallet, onTrade: onTrade)
              : BalanceCard(account: account, onTrade: onTrade)
          : RealBalanceCard(wallet: serverWallet, authenticated: authenticated);
      final favorites = assets
          .where((asset) => market.favorites.contains(asset.id))
          .take(3)
          .toList();
      return ListView(children: [
        const PrimeVestHeader(
            title: 'Overview', subtitle: 'Your Zettax workspace'),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 16, 28, 28),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: balance),
              const SizedBox(width: 22),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: PrimeVestDesignSystem.surfaceDark,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: const Color(0xFF40382F)),
                  ),
                  child: Column(children: [
                    SectionTitle(
                        title: 'Watchlist',
                        action: 'View markets',
                        onAction: onMarkets),
                    const SizedBox(height: 12),
                    if (favorites.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 28),
                        child: Text('Star markets to follow their prices here.',
                            style: TextStyle(
                                color: PrimeVestDesignSystem.textMuted)),
                      ),
                    for (final asset in favorites)
                      MarketTile(
                          asset: asset,
                          onTap: () => context.push('/asset/${asset.id}')),
                  ]),
                ),
              ),
            ]),
            const SizedBox(height: 28),
            const SectionTitle(title: 'Explore markets'),
            const SizedBox(height: 14),
            SizedBox(
                height: 98,
                child: Row(children: [
                  CategoryCard(
                      icon: Icons.currency_bitcoin,
                      title: 'Crypto',
                      subtitle: '4 assets',
                      onTap: onMarkets),
                  CategoryCard(
                      icon: Icons.currency_exchange,
                      title: 'Forex',
                      subtitle: '4 pairs',
                      onTap: onMarkets),
                  CategoryCard(
                      icon: Icons.show_chart,
                      title: 'Stocks',
                      subtitle: '4 assets',
                      onTap: onMarkets),
                  CategoryCard(
                      icon: Icons.account_balance,
                      title: 'Indices',
                      subtitle: '3 markets',
                      onTap: onMarkets),
                  CategoryCard(
                      icon: Icons.diamond_outlined,
                      title: 'Commodities',
                      subtitle: '3 assets',
                      onTap: onMarkets),
                ])),
            const SizedBox(height: 26),
            const SizedBox(width: 520, child: EducationCard()),
          ]),
        ),
      ]);
    }
    return CustomScrollView(slivers: [
      const SliverToBoxAdapter(
          child: PrimeVestHeader(
              title: 'Zettax', subtitle: 'Good morning, Investor')),
      SliverPadding(
        padding: const EdgeInsets.all(20),
        sliver: SliverList.list(children: [
          mode == AccountMode.demo
              ? authenticated
                  ? ServerBalanceCard(
                      wallet: serverWallet,
                      onTrade: onTrade,
                    )
                  : BalanceCard(account: account, onTrade: onTrade)
              : RealBalanceCard(
                  wallet: serverWallet,
                  authenticated: authenticated,
                ),
          const SizedBox(height: 24),
          SectionTitle(
              title: 'Watchlist', action: 'View markets', onAction: onMarkets),
          const SizedBox(height: 10),
          ...assets
              .where((asset) => market.favorites.contains(asset.id))
              .take(3)
              .map(
                (asset) => MarketTile(
                    asset: asset,
                    onTap: () => context.push('/asset/${asset.id}')),
              ),
          const SizedBox(height: 22),
          const SectionTitle(title: 'Explore markets'),
          const SizedBox(height: 12),
          SizedBox(
            height: 98,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              CategoryCard(
                  icon: Icons.currency_bitcoin,
                  title: 'Crypto',
                  subtitle: '4 assets',
                  onTap: onMarkets),
              CategoryCard(
                  icon: Icons.currency_exchange,
                  title: 'Forex',
                  subtitle: '4 pairs',
                  onTap: onMarkets),
              CategoryCard(
                  icon: Icons.show_chart,
                  title: 'Stocks',
                  subtitle: '4 assets',
                  onTap: onMarkets),
              CategoryCard(
                  icon: Icons.account_balance,
                  title: 'Indices',
                  subtitle: '3 markets',
                  onTap: onMarkets),
              CategoryCard(
                  icon: Icons.diamond_outlined,
                  title: 'Commodities',
                  subtitle: '3 assets',
                  onTap: onMarkets),
            ]),
          ),
          const SizedBox(height: 22),
          const EducationCard(),
        ]),
      ),
    ]);
  }
}

class ServerBalanceCard extends StatelessWidget {
  const ServerBalanceCard(
      {super.key, required this.wallet, required this.onTrade});
  final WalletSummary? wallet;
  final VoidCallback onTrade;

  @override
  Widget build(BuildContext context) {
    final available = wallet?.available ?? '—';
    final locked = wallet?.locked ?? '—';
    final equity = wallet?.equity ?? '—';
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF302A21), Color(0xFF24211E)],
        ),
        border: Border.all(color: const Color(0xFF453A29)),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Text('Demo portfolio',
              style: TextStyle(color: PrimeVestDesignSystem.textMuted)),
          Spacer(),
          Icon(Icons.cloud_done_outlined,
              color: PrimeVestDesignSystem.positive, size: 18),
        ]),
        const SizedBox(height: 8),
        Text('\$$equity',
            style: const TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w800,
                letterSpacing: -1.2)),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: MiniStat(label: 'Available', value: '\$$available')),
          Expanded(child: MiniStat(label: 'In positions', value: '\$$locked')),
        ]),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: onTrade,
          icon: const Icon(Icons.bolt),
          label: const Text('Start persisted demo trade'),
        ),
      ]),
    );
  }
}

class RealBalanceCard extends ConsumerWidget {
  static const fundingButtonStyle = ButtonStyle(
    minimumSize: WidgetStatePropertyAll(
        Size.fromHeight(PrimeVestDesignSystem.buttonHeight)),
    padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
    iconSize: WidgetStatePropertyAll(20),
    textStyle: WidgetStatePropertyAll(TextStyle(fontWeight: FontWeight.w700)),
    shape: WidgetStatePropertyAll(RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)))),
  );
  const RealBalanceCard({
    super.key,
    required this.wallet,
    required this.authenticated,
  });
  final WalletSummary? wallet;
  final bool authenticated;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final virtual = (ref.watch(systemConfigProvider).valueOrNull ??
            PublicSystemConfig.failClosed)
        .usesVirtualFunds;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF202B32), Color(0xFF222421)],
        ),
        border: Border.all(color: const Color(0x3348BDF8)),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(virtual ? 'VIRTUAL account' : 'REAL account',
              style: const TextStyle(color: PrimeVestDesignSystem.textMuted)),
          const Spacer(),
          const Icon(Icons.account_balance_outlined,
              color: Color(0xFF7DD3FC), size: 18),
        ]),
        const SizedBox(height: 8),
        Text(wallet == null ? '—' : '\$${wallet!.available}',
            style: const TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w800,
                letterSpacing: -1.2)),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
              child: MiniStat(
                  label: 'Available',
                  value: wallet == null ? '—' : '\$${wallet!.available}')),
          Expanded(
              child: MiniStat(
                  label: 'Locked',
                  value: wallet == null ? '—' : '\$${wallet!.locked}')),
        ]),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              style: fundingButtonStyle,
              onPressed: () =>
                  context.push(authenticated ? '/cash-in' : '/login'),
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Deposit'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              style: fundingButtonStyle,
              onPressed: () =>
                  context.push(authenticated ? '/withdraw' : '/login'),
              icon: const Icon(Icons.arrow_circle_up_outlined),
              label: const Text('Withdraw'),
            ),
          ),
        ]),
      ]),
    );
  }
}

class BalanceCard extends StatelessWidget {
  const BalanceCard({super.key, required this.account, required this.onTrade});
  final DemoAccountState account;
  final VoidCallback onTrade;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFF302A21), Color(0xFF24211E)]),
          border: Border.all(color: const Color(0xFF453A29)),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Text('Demo portfolio',
                style: TextStyle(color: PrimeVestDesignSystem.textMuted)),
            Spacer(),
            Icon(Icons.visibility_outlined,
                color: PrimeVestDesignSystem.textMuted, size: 18),
          ]),
          const SizedBox(height: 8),
          Text(usdFromCents(account.availablePaisa + account.lockedPaisa),
              style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.2)),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
                child: MiniStat(
                    label: 'Available',
                    value: usdFromCents(account.availablePaisa))),
            Expanded(
                child: MiniStat(
                    label: 'In positions',
                    value: usdFromCents(account.lockedPaisa))),
          ]),
          const SizedBox(height: 18),
          FilledButton.icon(
              onPressed: onTrade,
              icon: const Icon(Icons.bolt),
              label: const Text('Start demo trade')),
        ]),
      );
}

class MarketsPage extends ConsumerStatefulWidget {
  const MarketsPage({super.key, required this.onTrade});
  final VoidCallback onTrade;
  @override
  ConsumerState<MarketsPage> createState() => _MarketsPageState();
}

class _MarketsPageState extends ConsumerState<MarketsPage> {
  String search = '';
  String category = 'All';

  @override
  Widget build(BuildContext context) {
    final assetsAsync = ref.watch(assetsProvider);
    final favorites = ref.watch(marketProvider).favorites;
    return Column(children: [
      const PrimeVestHeader(
        title: 'Markets',
        subtitle: 'Live and reference market prices',
        actions: [CurrencySelector()],
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: TextField(
          onChanged: (value) =>
              setState(() => search = value.trim().toLowerCase()),
          decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search BTC, EUR/USD, Apple…'),
        ),
      ),
      SizedBox(
        height: 42,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          scrollDirection: Axis.horizontal,
          children: [
            'All',
            'Favorites',
            'Crypto',
            'Forex',
            'Stocks',
            'Indices',
            'Commodities'
          ]
              .map(
                (item) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                        label: Text(item),
                        selected: category == item,
                        onSelected: (_) => setState(() => category = item))),
              )
              .toList(),
        ),
      ),
      const SizedBox(height: 8),
      Expanded(
          child: assetsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) =>
            const Center(child: Text('Could not load demo markets')),
        data: (assets) {
          final filtered = assets.where((asset) {
            final matchesSearch = search.isEmpty ||
                '${asset.symbol} ${asset.name}'
                    .toLowerCase()
                    .replaceAll('/', '')
                    .contains(search.replaceAll('/', ''));
            final matchesCategory = category == 'All' ||
                (category == 'Favorites'
                    ? favorites.contains(asset.id)
                    : asset.assetClass == category);
            return matchesSearch && matchesCategory;
          }).toList();
          if (kIsWeb && MediaQuery.sizeOf(context).width >= 900) {
            return GridView.builder(
              padding: const EdgeInsets.fromLTRB(28, 14, 28, 28),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 470,
                mainAxisExtent: 86,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
              ),
              itemCount: filtered.length,
              itemBuilder: (_, index) {
                final asset = filtered[index];
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: PrimeVestDesignSystem.surfaceDark,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: const Color(0xFF40382F)),
                  ),
                  child: MarketTile(
                    asset: asset,
                    favorite: favorites.contains(asset.id),
                    onFavorite: () => ref
                        .read(marketProvider.notifier)
                        .toggleFavorite(asset.id),
                    onTap: () => context.push('/asset/${asset.id}'),
                  ),
                );
              },
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const SizedBox(height: 4),
            itemBuilder: (_, index) {
              final asset = filtered[index];
              return MarketTile(
                asset: asset,
                favorite: favorites.contains(asset.id),
                onFavorite: () =>
                    ref.read(marketProvider.notifier).toggleFavorite(asset.id),
                onTap: () => context.push('/asset/${asset.id}'),
              );
            },
          );
        },
      )),
    ]);
  }
}

class TradePage extends ConsumerStatefulWidget {
  const TradePage({super.key, required this.onBack});
  final VoidCallback onBack;
  @override
  ConsumerState<TradePage> createState() => _TradePageState();
}

class _ChartPeriod {
  const _ChartPeriod(
      this.id, this.shortLabel, this.menuLabel, this.interval, this.limit);

  final String id;
  final String shortLabel;
  final String menuLabel;
  final String interval;
  final int limit;
}

const _chartPeriods = <_ChartPeriod>[
  _ChartPeriod('1m', '1m', '1 minute', '1m', 120),
  _ChartPeriod('5m', '5m', '5 minutes', '5m', 120),
  _ChartPeriod('15m', '15m', '15 minutes', '15m', 120),
  _ChartPeriod('1h', '1h', '1 hour', '1h', 120),
  _ChartPeriod('1d', '1d', '1 day', '1d', 120),
  _ChartPeriod('1W', '1W', '1 week', '1h', 168),
  _ChartPeriod('1M', '1M', '1 month', '4h', 180),
  _ChartPeriod('6M', '6M', '6 months', '1d', 180),
  _ChartPeriod('1Y', '1Y', '1 year', '1w', 52),
  _ChartPeriod('3Y', '3Y', '3 years', '1w', 156),
  _ChartPeriod('5Y', '5Y', '5 years', '1M', 60),
];

class _TradePageState extends ConsumerState<TradePage> {
  bool timed = true;
  bool submitting = false;
  final Set<String> closingPositions = {};
  final Map<String, ({double price, double stake})> displayEntries = {};
  late final Timer clock;

  @override
  void initState() {
    super.initState();
    clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      if (DateTime.now().second % 5 == 0 &&
          ref.read(sessionProvider).phase == SessionPhase.authenticated) {
        ref.invalidate(
            positionsProvider(ref.read(selectedAccountModeProvider)));
        ref.invalidate(
            timedContractsProvider(ref.read(selectedAccountModeProvider)));
      }
    });
  }

  @override
  void dispose() {
    clock.cancel();
    super.dispose();
  }

  String remaining(DateTime? end) {
    if (end == null) return 'Open';
    return contractTimeRemaining(end);
  }

  Future<void> closeOpenPosition(
      String id, bool authenticated, AccountMode mode) async {
    if (closingPositions.contains(id)) return;
    setState(() => closingPositions.add(id));
    try {
      if (authenticated) {
        await ref.read(tradingRepositoryProvider).closePosition(id);
        ref.invalidate(positionsProvider(mode));
        ref.invalidate(accountsProvider);
      } else {
        ref.read(demoAccountProvider.notifier).closePosition(id);
      }
      if (mounted) _result(context, true, 'Position closed');
    } on ApiFailure catch (error) {
      if (mounted) _result(context, false, error.message);
    } finally {
      if (mounted) setState(() => closingPositions.remove(id));
    }
  }

  double amount = 10;
  int durationSeconds = 30;
  String periodId = '1m';

  Future<void> _editContractValue(bool duration) async {
    final virtual = (ref.read(systemConfigProvider).valueOrNull ??
            PublicSystemConfig.failClosed)
        .usesVirtualFunds;
    final minimumStake = virtual ? 0.01 : 10.0;
    final controller = TextEditingController(
        text: duration ? '$durationSeconds' : amount.toStringAsFixed(2));
    final form = GlobalKey<FormState>();
    final result = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(duration ? 'Contract duration' : 'Stake in USD'),
              content: Form(
                  key: form,
                  child: TextFormField(
                    controller: controller,
                    autofocus: true,
                    keyboardType:
                        TextInputType.numberWithOptions(decimal: !duration),
                    decoration: InputDecoration(
                        helperText: duration
                            ? 'Seconds: 30–31,536,000 (365 days)'
                            : 'Minimum \$${minimumStake.toStringAsFixed(2)} · up to available balance'),
                    validator: (value) {
                      if (duration) {
                        final parsed = int.tryParse(value ?? '');
                        return parsed == null ||
                                parsed < 30 ||
                                parsed > 31536000
                            ? 'Enter 30–31,536,000 seconds'
                            : null;
                      }
                      if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(value ?? '')) {
                        return 'Use up to two decimal places';
                      }
                      final parsed = double.tryParse(value ?? '');
                      return parsed == null ||
                              !parsed.isFinite ||
                              parsed < minimumStake
                          ? 'Minimum stake is \$${minimumStake.toStringAsFixed(2)}'
                          : null;
                    },
                  )),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel')),
                TextButton(
                    onPressed: () {
                      if (form.currentState!.validate()) {
                        Navigator.pop(context, controller.text);
                      }
                    },
                    child: const Text('Apply'))
              ],
            ));
    if (result != null && mounted) {
      setState(() {
        if (duration) {
          durationSeconds = int.parse(result);
        } else {
          amount = double.parse(result);
        }
      });
    }
    // Wait for the route's reverse animation before disposing its text controller.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final assets = ref.watch(assetsProvider).value ?? const <MarketAsset>[];
    if (assets.isEmpty) return const Center(child: CircularProgressIndicator());
    var assetId = ref.watch(selectedAssetProvider);
    final asset =
        assets.where((item) => item.id == assetId).firstOrNull ?? assets.first;
    assetId = asset.id;
    final period =
        _chartPeriods.where((item) => item.id == periodId).firstOrNull ??
            _chartPeriods.first;
    final candleRequest = (
      assetId: asset.id,
      interval: period.interval,
      limit: period.limit,
    );
    final displaySeries = ref.watch(liveCandlesProvider(candleRequest));
    final minuteSeries = ref.watch(
        liveCandlesProvider((assetId: asset.id, interval: '1m', limit: 120)));
    final dailyHistory = ref.watch(dailyPerformanceProvider(asset.id));
    final providerTime = displaySeries.valueOrNull?.providerTimestamp;
    final utcNow = DateTime.now().toUtc();
    final performanceAsOf = providerTime != null && providerTime.isAfter(utcNow)
        ? utcNow
        : providerTime;
    // Demo order accounting remains isolated from external display feeds.
    final executionPrice =
        ref.watch(marketProvider).prices[asset.id] ?? asset.price;
    final livePrice = displaySeries.valueOrNull?.candles.lastOrNull?.close;
    final demoAccount = ref.watch(demoAccountProvider);
    final available = demoAccount.availablePaisa;
    final mode = ref.watch(selectedAccountModeProvider);
    final demoSelected = mode == AccountMode.demo;
    final tradingConfig = ref.watch(systemConfigProvider).valueOrNull ??
        PublicSystemConfig.failClosed;
    final tradingAvailable = tradingConfig.tradingAvailableFor(mode);
    final authenticated =
        ref.watch(sessionProvider).phase == SessionPhase.authenticated;
    final virtual = (ref.watch(systemConfigProvider).valueOrNull ??
            PublicSystemConfig.failClosed)
        .usesVirtualFunds;
    final minimumStake = virtual ? 0.01 : 10.0;
    final stakeStep = virtual ? 1.0 : 10.0;
    final serverAccounts =
        ref.watch(accountsProvider).value ?? const <AccountSummary>[];
    final selectedServerAccount =
        serverAccounts.where((account) => account.mode == mode).firstOrNull;
    final serverWallet = selectedServerAccount?.wallets.firstOrNull;
    final availableLabel = authenticated
        ? serverWallet == null
            ? '—'
            : '\$${serverWallet.available}'
        : demoSelected
            ? usdFromCents(available)
            : 'Sign in';
    final displayPrice = livePrice == null
        ? '—'
        : asset.assetClass.toLowerCase() == 'crypto'
            ? '${livePrice.toStringAsFixed(asset.precision)} USDT'
            : formatDisplayPrice(
                value: livePrice,
                precision: asset.precision,
                quoteAsset: asset.quoteAsset,
              );
    final serverPositions = authenticated
        ? ref.watch(positionsProvider(mode)).valueOrNull ?? const []
        : const [];
    final serverContracts = authenticated
        ? ref.watch(timedContractsProvider(mode)).valueOrNull ?? const []
        : const [];
    final tradeMarkers = <ChartTradeMarker>[];
    void addMarker(String id, DateTime openedAt, DateTime? endsAt, String side,
        {double profitFeeRate = 0, double? entryPrice, double? stakeAmount}) {
      final entry = entryPrice != null && stakeAmount != null
          ? (price: entryPrice, stake: stakeAmount)
          : displayEntries[id];
      // Never substitute a simulated fill for a missing live entry observation.
      if (entry == null || livePrice == null) return;
      final estimate = estimateContractReturn(
        stake: entry.stake,
        entryPrice: entry.price,
        currentPrice: livePrice,
        up: side == 'BUY' || side == 'UP',
        profitFeeRate: profitFeeRate,
      );
      final awaitingSettlement =
          endsAt != null && !endsAt.isAfter(DateTime.now());
      final color = estimate.pnl > 0
          ? PrimeVestDesignSystem.positive
          : estimate.pnl < 0
              ? PrimeVestDesignSystem.negative
              : PrimeVestDesignSystem.primaryGold;
      final stake = formatUsdAmount(entry.stake);
      final current = formatUsdAmount(estimate.returnAmount);
      final pnl = formatUsdAmount(estimate.pnl.abs());
      final pnlSign = estimate.pnl > 0
          ? '+'
          : estimate.pnl < 0
              ? '-'
              : '';
      final rounded =
          estimate.pnl == 0 && estimate.rawPnl != 0 ? ' (rounded to zero)' : '';
      tradeMarkers.add(ChartTradeMarker(
          id: id,
          openedAt: openedAt,
          endsAt: endsAt,
          price: entry.price,
          color: awaitingSettlement ? PrimeVestDesignSystem.primaryGold : color,
          label: awaitingSettlement
              ? '$side $stake'
              : '$side · Now $current · P/L $pnlSign$pnl$rounded'));
    }

    if (authenticated) {
      for (final position in serverPositions) {
        if (position.instrumentId == asset.id && position.status == 'OPEN') {
          final entry = double.tryParse(position.averageEntry);
          final quantity = double.tryParse(position.quantity);
          addMarker(position.id, position.openedAt, null, position.side,
              entryPrice: entry,
              stakeAmount:
                  entry == null || quantity == null ? null : entry * quantity);
        }
      }
      for (final contract in serverContracts) {
        if (contract.instrumentId == asset.id && contract.result == 'PENDING') {
          if (contract.settlementModel == 'PROPORTIONAL_V2') {
            displayEntries[contract.id] = (
              price: double.parse(contract.entryPrice),
              stake: double.parse(contract.investmentAmount)
            );
          }
          addMarker(contract.id, contract.entryTimestamp,
              contract.expiryTimestamp, contract.direction,
              profitFeeRate: double.tryParse(contract.profitFeeRate) ?? 0,
              entryPrice: double.tryParse(contract.entryPrice),
              stakeAmount: double.tryParse(contract.investmentAmount));
        }
      }
    } else {
      for (final position in demoAccount.positions) {
        if (position.assetId == asset.id) {
          addMarker(position.id, position.openedAt, null,
              position.side.name.toUpperCase());
        }
      }
      for (final contract in demoAccount.contracts) {
        if (contract.assetId == asset.id &&
            contract.result == ContractResult.pending) {
          addMarker(contract.id, contract.entryTimestamp,
              contract.expiryTimestamp, contract.direction.name.toUpperCase());
        }
      }
    }

    final activeTrades = <_ActiveTradeItem>[];
    if (authenticated) {
      for (final position
          in serverPositions.where((item) => item.status == 'OPEN')) {
        final pnl = double.tryParse(position.unrealizedPnl);
        activeTrades.add(_ActiveTradeItem(
          id: position.id,
          assetId: position.instrumentId,
          title: position.instrumentId.toUpperCase(),
          detail: '${position.side} · Open-ended · Paper P/L',
          value: pnl == null
              ? '—'
              : '${pnl >= 0 ? '+' : '-'}\$${pnl.abs().toStringAsFixed(2)}',
          positive: pnl == null || pnl >= 0,
          onClose: closingPositions.contains(position.id)
              ? null
              : () => closeOpenPosition(position.id, true, mode),
        ));
      }
      for (final contract
          in serverContracts.where((item) => item.result == 'PENDING')) {
        final entry = double.tryParse(contract.entryPrice);
        final stake = double.tryParse(contract.investmentAmount);
        final estimate = contract.instrumentId == asset.id &&
                livePrice != null &&
                entry != null &&
                stake != null
            ? estimateContractReturn(
                stake: stake,
                entryPrice: entry,
                currentPrice: livePrice,
                up: contract.direction == 'UP',
                profitFeeRate: double.tryParse(contract.profitFeeRate) ?? 0)
            : null;
        activeTrades.add(_ActiveTradeItem(
          id: contract.id,
          assetId: contract.instrumentId,
          title: contract.instrumentId.toUpperCase(),
          detail:
              '${contract.direction} · Timed · ${remaining(contract.expiryTimestamp)}',
          value: estimate == null
              ? 'Stake \$${contract.investmentAmount}'
              : 'Est. ${estimate.pnl >= 0 ? '+' : '-'}\$${estimate.pnl.abs().toStringAsFixed(2)}',
          positive: estimate == null || estimate.pnl >= 0,
        ));
      }
    } else if (demoSelected) {
      final prices = ref.watch(marketProvider).prices;
      for (final position in demoAccount.positions) {
        final price = prices[position.assetId] ?? position.entryPrice;
        final pnl = (price - position.entryPrice) *
            position.quantity *
            (position.side == TradeSide.buy ? 1 : -1);
        activeTrades.add(_ActiveTradeItem(
          id: position.id,
          assetId: position.assetId,
          title: position.assetId.toUpperCase(),
          detail: '${position.side.name.toUpperCase()} · Open-ended · Demo P/L',
          value: '${pnl >= 0 ? '+' : '-'}\$${pnl.abs().toStringAsFixed(2)}',
          positive: pnl >= 0,
          onClose: closingPositions.contains(position.id)
              ? null
              : () => closeOpenPosition(position.id, false, mode),
        ));
      }
      for (final contract in demoAccount.contracts
          .where((item) => item.result == ContractResult.pending)) {
        activeTrades.add(_ActiveTradeItem(
          id: contract.id,
          assetId: contract.assetId,
          title: contract.assetId.toUpperCase(),
          detail:
              '${contract.direction.name.toUpperCase()} · Timed · ${remaining(contract.expiryTimestamp)}',
          value: 'Stake ${usdFromCents(contract.investmentPaisa)}',
          positive: true,
        ));
      }
    }

    Future<void> normal(TradeSide side) async {
      final observed = ref
          .read(liveCandlesProvider(candleRequest))
          .valueOrNull
          ?.candles
          .lastOrNull
          ?.close;
      if (observed == null || observed <= 0) {
        _result(
            context, false, 'Wait for a live price before placing a trade.');
        return;
      }
      final displayEntry = (price: observed, stake: amount.toDouble());
      if (authenticated) {
        try {
          final quantity = (amount / executionPrice).toStringAsFixed(8);
          final order =
              await ref.read(tradingRepositoryProvider).createMarketOrder(
                    mode: mode,
                    instrumentId: asset.id,
                    side: side.name.toUpperCase(),
                    quantity: quantity,
                  );
          ref.invalidate(accountsProvider);
          if (order.positionId != null) {
            displayEntries[order.positionId!] = displayEntry;
          }
          ref.invalidate(positionsProvider(mode));
          if (context.mounted) {
            _result(context, true, '${side.name.toUpperCase()} order saved');
          }
        } on ApiFailure catch (error) {
          if (context.mounted) _result(context, false, error.message);
        }
        return;
      }
      final ok = ref.read(demoAccountProvider.notifier).openPosition(
            asset.id,
            side,
            (amount * 100).round(),
          );
      if (ok) {
        final item = ref.read(demoAccountProvider).positions.last;
        displayEntries[item.id] = displayEntry;
      }
      _result(
          context,
          ok,
          ok
              ? '${side.name.toUpperCase()} position opened'
              : 'Insufficient demo funds');
    }

    Future<void> contract(ContractDirection direction) async {
      final feeRate = authenticated
          ? await ref.read(tradingRepositoryProvider).profitFeeRate()
          : '0';
      if (!context.mounted) return;
      final observed = ref
          .read(liveCandlesProvider(candleRequest))
          .valueOrNull
          ?.candles
          .lastOrNull
          ?.close;
      if (observed == null || observed <= 0) {
        _result(
            context, false, 'Wait for a live price before placing a trade.');
        return;
      }
      final displayEntry = (price: observed, stake: amount.toDouble());
      if (authenticated) {
        try {
          final created =
              await ref.read(tradingRepositoryProvider).createTimedContract(
                    mode: mode,
                    instrumentId: asset.id,
                    direction: direction.name.toUpperCase(),
                    investmentAmount: amount.toStringAsFixed(2),
                    durationSeconds: durationSeconds,
                    expectedProfitFeeRate: feeRate,
                  );
          ref.invalidate(accountsProvider);
          displayEntries[created.id] = displayEntry;
          ref.invalidate(timedContractsProvider(mode));
          if (context.mounted) {
            _result(context, true,
                '${direction.name.toUpperCase()} contract saved');
          }
        } on ApiFailure catch (error) {
          if (context.mounted) _result(context, false, error.message);
        }
        return;
      }
      final ok = ref.read(demoAccountProvider.notifier).openContract(
          asset.id,
          direction,
          (amount * 100).round(),
          Duration(seconds: durationSeconds));
      if (ok) {
        final item = ref.read(demoAccountProvider).contracts.first;
        displayEntries[item.id] = displayEntry;
      }
      _result(
          context,
          ok,
          ok
              ? '${direction.name.toUpperCase()} contract started'
              : 'Insufficient demo funds');
    }

    Future<void> submit(bool buy) async {
      if (!authenticated && !(kIsWeb && demoSelected)) {
        context.push('/login');
        return;
      }
      if (submitting) return;
      setState(() => submitting = true);
      try {
        final repository = ref.read(tradingRepositoryProvider);
        final pending = timed && authenticated
            ? await repository.pendingTimedContract()
            : null;
        if (!context.mounted) return;
        if (pending != null) {
          final body = pending['body'] as Map;
          final retry = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                    title: const Text('Resolve previous trade'),
                    content: Text(
                        'The result of your previous ${body['direction']} ${body['instrumentId']} trade for \$${body['investmentAmount']} is uncertain.\n\nRetry the same request? If it was already accepted, no second trade is opened. If it was not accepted, retrying can open it now with its original amount and duration.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Not now')),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Retry original request')),
                    ],
                  ));
          if (retry == true) {
            await repository.retryPendingTimedContract();
            ref.invalidate(accountsProvider);
            ref.invalidate(timedContractsProvider(AccountMode.demo));
            ref.invalidate(timedContractsProvider(AccountMode.real));
            if (context.mounted) {
              _result(context, true,
                  'Previous trade request resolved. Check your portfolio.');
            }
          }
          return;
        }
        if (timed) {
          await contract(buy ? ContractDirection.up : ContractDirection.down);
        } else {
          await normal(buy ? TradeSide.buy : TradeSide.sell);
        }
      } on ApiFailure catch (error) {
        if (context.mounted) _result(context, false, error.message);
      } catch (_) {
        if (context.mounted) {
          _result(context, false, 'Unable to place trade. Please try again.');
        }
      } finally {
        if (mounted) setState(() => submitting = false);
      }
    }

    if (kIsWeb && MediaQuery.sizeOf(context).width >= 900) {
      final compactDesktop = MediaQuery.sizeOf(context).width < 1200;
      final chart = displaySeries.when(
        data: (series) => LiveTradeChart(
          key: ValueKey('${asset.id}:${period.id}'),
          series: series,
          precision: asset.precision,
          markers: tradeMarkers,
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: TextButton.icon(
            onPressed: () => ref.invalidate(liveCandlesProvider(candleRequest)),
            icon: const Icon(Icons.refresh),
            label: const Text('Retry market connection'),
          ),
        ),
      );
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.candlestick_chart_outlined,
                  color: PrimeVestDesignSystem.primaryGold, size: 25),
              const SizedBox(width: 12),
              const Text('Trading workspace',
                  style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800)),
              const SizedBox(width: 16),
              Text(demoSelected ? 'DEMO MARKET' : 'LIVE MARKET',
                  style: const TextStyle(
                      color: PrimeVestDesignSystem.textMuted,
                      fontSize: 11,
                      letterSpacing: 1.2)),
              const Spacer(),
              const CurrencySelector(),
            ]),
            const SizedBox(height: 18),
            Expanded(
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: PrimeVestDesignSystem.surfaceDark,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFF40382F)),
                        ),
                        child: Column(children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                            child: Row(children: [
                              IconButton(
                                tooltip: 'Favorite instrument',
                                onPressed: () => ref
                                    .read(marketProvider.notifier)
                                    .toggleFavorite(asset.id),
                                icon: Icon(
                                  ref
                                          .watch(marketProvider)
                                          .favorites
                                          .contains(asset.id)
                                      ? Icons.star_rounded
                                      : Icons.star_border_rounded,
                                  color: PrimeVestDesignSystem.primaryGold,
                                ),
                              ),
                              SizedBox(
                                width: compactDesktop ? 170 : 230,
                                child: DropdownButtonFormField<String>(
                                  key: ValueKey('desktop-${asset.id}'),
                                  initialValue: asset.id,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 11),
                                  ),
                                  items: assets
                                      .map((item) => DropdownMenuItem(
                                            value: item.id,
                                            child: Row(children: [
                                              AssetIcon(asset: item, size: 22),
                                              const SizedBox(width: 8),
                                              Flexible(
                                                child: Text(item.symbol,
                                                    overflow:
                                                        TextOverflow.ellipsis),
                                              ),
                                            ]),
                                          ))
                                      .toList(),
                                  onChanged: submitting
                                      ? null
                                      : (value) => ref
                                          .read(selectedAssetProvider.notifier)
                                          .state = value ?? asset.id,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Flexible(
                                child: Text(displayPrice,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 21,
                                        fontWeight: FontWeight.w800)),
                              ),
                              if (!compactDesktop) const Spacer(),
                              if (!compactDesktop)
                                Text(
                                  displaySeries.valueOrNull?.freshness ==
                                          'SAMPLED'
                                      ? '● Sampled real price'
                                      : displaySeries.valueOrNull?.freshness ==
                                              'SIMULATED'
                                          ? '● Simulated'
                                          : displaySeries
                                                      .valueOrNull?.delivery ==
                                                  'WEBSOCKET'
                                              ? '● Live'
                                              : '● Updating',
                                  style: const TextStyle(
                                      color: PrimeVestDesignSystem.primaryGold,
                                      fontSize: 11),
                                ),
                              const SizedBox(width: 12),
                              PopupMenuButton<String>(
                                key:
                                    const ValueKey('desktop-chart-period-menu'),
                                initialValue: periodId,
                                tooltip: 'Chart period',
                                onSelected: (value) =>
                                    setState(() => periodId = value),
                                itemBuilder: (_) => _chartPeriods
                                    .map((value) => PopupMenuItem(
                                        value: value.id,
                                        child: Text(value.menuLabel)))
                                    .toList(),
                                child: Chip(label: Text(period.shortLabel)),
                              ),
                            ]),
                          ),
                          Expanded(child: chart),
                          SizedBox(
                            height: 47,
                            child: MarketPerformanceStrip(
                              history: dailyHistory.valueOrNull,
                              minuteSeries: minuteSeries.valueOrNull,
                              precision: asset.precision,
                              latestPrice: livePrice,
                              asOf: performanceAsOf,
                              loading: dailyHistory.isLoading,
                            ),
                          ),
                          _ActiveTradesStrip(
                            items: activeTrades,
                            onSelect: (id) => ref
                                .read(selectedAssetProvider.notifier)
                                .state = id,
                          ),
                        ]),
                      ),
                    ),
                    const SizedBox(width: 18),
                    SizedBox(
                      width: compactDesktop ? 280 : 320,
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: PrimeVestDesignSystem.surfaceDark,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFF40382F)),
                        ),
                        child: SingleChildScrollView(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                              Row(children: [
                                const Expanded(
                                  child: Text('Place a trade',
                                      style: TextStyle(
                                          fontSize: 19,
                                          fontWeight: FontWeight.w800)),
                                ),
                                const AccountModeSelector(),
                              ]),
                              const SizedBox(height: 4),
                              Text(
                                  demoSelected
                                      ? 'Practice with virtual funds'
                                      : 'Trade with your account balance',
                                  style: const TextStyle(
                                      color: PrimeVestDesignSystem.textMuted,
                                      fontSize: 12)),
                              const SizedBox(height: 24),
                              const Text('AVAILABLE BALANCE',
                                  style: TextStyle(
                                      color: PrimeVestDesignSystem.textMuted,
                                      letterSpacing: 1,
                                      fontSize: 11)),
                              const SizedBox(height: 6),
                              Text(availableLabel,
                                  style: const TextStyle(
                                      fontSize: 30,
                                      fontWeight: FontWeight.w800,
                                      color:
                                          PrimeVestDesignSystem.primaryGold)),
                              if (authenticated && serverWallet != null)
                                Text('Locked: \$${serverWallet.locked}',
                                    style: const TextStyle(
                                        color: PrimeVestDesignSystem.textMuted,
                                        fontSize: 12)),
                              const Divider(height: 38),
                              _TradeModeSelector(
                                timed: timed,
                                onChanged: submitting
                                    ? null
                                    : (value) => setState(() => timed = value),
                              ),
                              const SizedBox(height: 18),
                              const Text('Investment',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w700)),
                              const SizedBox(height: 8),
                              SizedBox(
                                height: 42,
                                child: _TradeStepper(
                                  label: 'Investment',
                                  value: formatUsdAmount(amount),
                                  onTap: submitting
                                      ? null
                                      : () => _editContractValue(false),
                                  decrease: submitting || amount <= minimumStake
                                      ? null
                                      : () => setState(() => amount =
                                          (amount - stakeStep).clamp(
                                              minimumStake, double.infinity)),
                                  increase: submitting
                                      ? null
                                      : () =>
                                          setState(() => amount += stakeStep),
                                ),
                              ),
                              const SizedBox(height: 18),
                              Text(timed ? 'Duration' : 'Closing',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 8),
                              if (timed)
                                SizedBox(
                                  height: 42,
                                  child: _TradeStepper(
                                    label: 'Duration',
                                    value: durationSeconds >= 86400
                                        ? '${durationSeconds ~/ 86400}d ${(durationSeconds % 86400) ~/ 3600}h'
                                        : '${(durationSeconds ~/ 3600).toString().padLeft(2, '0')}:${((durationSeconds % 3600) ~/ 60).toString().padLeft(2, '0')}:${(durationSeconds % 60).toString().padLeft(2, '0')}',
                                    onTap: submitting
                                        ? null
                                        : () => _editContractValue(true),
                                    decrease: submitting
                                        ? null
                                        : () => setState(() => durationSeconds =
                                            (durationSeconds - 30)
                                                .clamp(30, 31536000)),
                                    increase: submitting
                                        ? null
                                        : () => setState(() => durationSeconds =
                                            (durationSeconds + 30)
                                                .clamp(30, 31536000)),
                                  ),
                                )
                              else
                                const Text(
                                    'No expiry · close manually. Paper P/L uses simulated prices.',
                                    style: TextStyle(
                                        color: PrimeVestDesignSystem.textMuted,
                                        fontSize: 12)),
                              if (timed)
                                _DurationPresets(
                                  value: durationSeconds,
                                  onSelected: submitting
                                      ? null
                                      : (value) => setState(
                                          () => durationSeconds = value),
                                ),
                              const SizedBox(height: 24),
                              if (!tradingAvailable)
                                const Padding(
                                  padding: EdgeInsets.only(bottom: 12),
                                  child: Text(
                                      'Trading is not available in this mode.',
                                      style: TextStyle(
                                          color:
                                              PrimeVestDesignSystem.negative)),
                                ),
                              SizedBox(
                                height: 48,
                                child: TradeButton(
                                  label: submitting
                                      ? 'Please wait…'
                                      : timed
                                          ? 'BUY ↑'
                                          : 'BUY',
                                  icon: Icons.north_east,
                                  onPressed: tradingAvailable &&
                                          !submitting &&
                                          executionPrice > 0
                                      ? () => submit(true)
                                      : null,
                                ),
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                height: 48,
                                child: TradeButton(
                                  label: submitting
                                      ? 'Please wait…'
                                      : timed
                                          ? 'SELL ↓'
                                          : 'SELL',
                                  icon: Icons.south_west,
                                  negative: true,
                                  onPressed: tradingAvailable &&
                                          !submitting &&
                                          executionPrice > 0
                                      ? () => submit(false)
                                      : null,
                                ),
                              ),
                            ])),
                      ),
                    ),
                  ]),
            ),
          ]),
        ),
      );
    }

    return SafeArea(
      bottom: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(2, 3, 0, 3),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
                color: PrimeVestDesignSystem.surfaceDark,
                borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              IconButton(
                  key: const ValueKey('trade-back-button'),
                  tooltip: 'Back',
                  onPressed: widget.onBack,
                  icon: const Icon(Icons.arrow_back, size: 20),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints.tightFor(width: 30, height: 36)),
              const ZettaxMark(height: 20),
              const SizedBox(width: 6),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('${mode.apiValue} BALANCE · USD',
                        style: const TextStyle(
                            fontSize: 8,
                            color: PrimeVestDesignSystem.textMuted,
                            letterSpacing: 1)),
                    Text(availableLabel,
                        style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: PrimeVestDesignSystem.primaryGold)),
                    if (authenticated && serverWallet != null)
                      Text('Available · Locked \$${serverWallet.locked}',
                          style: const TextStyle(
                              fontSize: 8,
                              color: PrimeVestDesignSystem.textMuted)),
                  ])),
              const AccountModeSelector(),
            ]),
          ),
          const SizedBox(height: 3),
          if (!tradingAvailable)
            Row(children: [
              Expanded(
                  child: TextButton.icon(
                      onPressed: () =>
                          context.push(authenticated ? '/cash-in' : '/login'),
                      icon: const Icon(Icons.add_circle_outline, size: 18),
                      label: const Text('Deposit'))),
              Expanded(
                  child: TextButton.icon(
                      onPressed: () =>
                          context.push(authenticated ? '/withdraw' : '/login'),
                      icon:
                          const Icon(Icons.arrow_circle_up_outlined, size: 18),
                      label: const Text('Withdraw'))),
            ]),
          Row(children: [
            IconButton(
                visualDensity: VisualDensity.compact,
                constraints:
                    const BoxConstraints.tightFor(width: 32, height: 34),
                tooltip: 'Favorite instrument',
                onPressed: () =>
                    ref.read(marketProvider.notifier).toggleFavorite(asset.id),
                icon: Icon(
                    ref.watch(marketProvider).favorites.contains(asset.id)
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    color: PrimeVestDesignSystem.primaryGold)),
            Expanded(
                child: DropdownButtonFormField<String>(
              key: ValueKey(asset.id),
              initialValue: asset.id,
              isExpanded: true,
              decoration: const InputDecoration(
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
              items: assets
                  .map((item) => DropdownMenuItem(
                      value: item.id,
                      child: Row(children: [
                        AssetIcon(asset: item, size: 22),
                        const SizedBox(width: 6),
                        Flexible(
                            child: Text(
                          item.assetClass.toLowerCase() == 'crypto'
                              ? '${item.symbol.split('/').first}/USDT'
                              : item.symbol,
                          overflow: TextOverflow.ellipsis,
                        )),
                      ])))
                  .toList(),
              onChanged: submitting
                  ? null
                  : (value) => ref.read(selectedAssetProvider.notifier).state =
                      value ?? asset.id,
            )),
            const SizedBox(width: 4),
            const CurrencySelector(),
          ]),
          const SizedBox(height: 2),
          Row(children: [
            Text(displayPrice,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const Spacer(),
            Text(
                displaySeries.valueOrNull?.freshness == 'SAMPLED'
                    ? '● Sampled real price'
                    : displaySeries.valueOrNull?.freshness == 'SIMULATED'
                        ? '● Simulated'
                        : displaySeries.valueOrNull != null &&
                                DateTime.now()
                                        .difference(displaySeries
                                            .valueOrNull!.receivedAt)
                                        .inSeconds >
                                    30
                            ? '● Delayed'
                            : displaySeries.valueOrNull?.delivery == 'WEBSOCKET'
                                ? '● Live'
                                : '● Updating',
                style: const TextStyle(
                    color: PrimeVestDesignSystem.primaryGold, fontSize: 9)),
            PopupMenuButton<String>(
              key: const ValueKey('chart-period-menu'),
              initialValue: periodId,
              tooltip: 'Chart period',
              onSelected: (value) => setState(() => periodId = value),
              itemBuilder: (_) => _chartPeriods
                  .map((value) => PopupMenuItem(
                      value: value.id, child: Text(value.menuLabel)))
                  .toList(),
              child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Text(period.shortLabel)),
            ),
          ]),
          Expanded(
            child: displaySeries.when(
              data: (series) => LiveTradeChart(
                key: ValueKey('${asset.id}:${period.id}'),
                series: series,
                precision: asset.precision,
                markers: tradeMarkers,
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => Center(
                  child: TextButton.icon(
                      onPressed: () =>
                          ref.invalidate(liveCandlesProvider(candleRequest)),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry market connection'))),
            ),
          ),
          SizedBox(
            height: 47,
            child: MarketPerformanceStrip(
              history: dailyHistory.valueOrNull,
              minuteSeries: minuteSeries.valueOrNull,
              precision: asset.precision,
              latestPrice: livePrice,
              asOf: performanceAsOf,
              loading: dailyHistory.isLoading,
            ),
          ),
          _ActiveTradesStrip(
            items: activeTrades,
            onSelect: (id) =>
                ref.read(selectedAssetProvider.notifier).state = id,
          ),
          _TradeModeSelector(
            timed: timed,
            compact: true,
            onChanged:
                submitting ? null : (value) => setState(() => timed = value),
          ),
          const SizedBox(height: 2),
          Row(children: [
            Expanded(
                child: SizedBox(
              key: const ValueKey('trade-amount-control'),
              height: 36,
              child: _TradeStepper(
                label: 'Investment',
                value: formatUsdAmount(amount.toDouble()),
                onTap: submitting ? null : () => _editContractValue(false),
                decrease: submitting || amount <= minimumStake
                    ? null
                    : () => setState(() => amount = (amount - stakeStep)
                        .clamp(minimumStake, double.infinity)),
                increase: submitting
                    ? null
                    : () => setState(() => amount += stakeStep),
              ),
            )),
            const SizedBox(width: 10),
            if (timed)
              Expanded(
                  child: SizedBox(
                key: const ValueKey('trade-duration-control'),
                height: 36,
                child: _TradeStepper(
                  label: 'Duration',
                  value: durationSeconds >= 86400
                      ? '${durationSeconds ~/ 86400}d ${(durationSeconds % 86400) ~/ 3600}h'
                      : '${(durationSeconds ~/ 3600).toString().padLeft(2, '0')}:${((durationSeconds % 3600) ~/ 60).toString().padLeft(2, '0')}:${(durationSeconds % 60).toString().padLeft(2, '0')}',
                  onTap: submitting ? null : () => _editContractValue(true),
                  decrease: submitting
                      ? null
                      : () => setState(() => durationSeconds =
                          (durationSeconds - 30).clamp(30, 31536000)),
                  increase: submitting
                      ? null
                      : () => setState(() => durationSeconds =
                          (durationSeconds + 30).clamp(30, 31536000)),
                ),
              ))
            else
              const Expanded(
                  child: Center(
                      child: Text('No expiry · manual close · paper price',
                          style: TextStyle(
                              fontSize: 11,
                              color: PrimeVestDesignSystem.textMuted)))),
          ]),
          if (timed)
            _DurationPresets(
              value: durationSeconds,
              compact: true,
              onSelected: submitting
                  ? null
                  : (value) => setState(() => durationSeconds = value),
            ),
          const SizedBox(height: 3),
          Row(children: [
            Expanded(
                child: SizedBox(
                    key: const ValueKey('trade-sell-button'),
                    height: 40,
                    child: TradeButton(
                        label: submitting
                            ? 'Please wait…'
                            : timed
                                ? 'SELL ↓'
                                : 'SELL',
                        icon: Icons.south_west,
                        negative: true,
                        onPressed: tradingAvailable &&
                                !submitting &&
                                executionPrice > 0
                            ? () => submit(false)
                            : null))),
            const SizedBox(width: 10),
            Expanded(
                child: SizedBox(
                    key: const ValueKey('trade-buy-button'),
                    height: 40,
                    child: TradeButton(
                        label: submitting
                            ? 'Please wait…'
                            : timed
                                ? 'BUY ↑'
                                : 'BUY',
                        icon: Icons.north_east,
                        onPressed: tradingAvailable &&
                                !submitting &&
                                executionPrice > 0
                            ? () => submit(true)
                            : null))),
          ]),
        ]),
      ),
    );
  }
}

class PortfolioPage extends ConsumerStatefulWidget {
  const PortfolioPage({super.key});
  @override
  ConsumerState<PortfolioPage> createState() => _PortfolioPageState();
}

class _PortfolioPageState extends ConsumerState<PortfolioPage> {
  int tab = 0;
  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(selectedAccountModeProvider);
    final authenticated =
        ref.watch(sessionProvider).phase == SessionPhase.authenticated;
    if (authenticated) {
      final accounts = ref.watch(accountsProvider);
      final positions = ref.watch(positionsProvider(mode));
      final timedContracts = ref.watch(timedContractsProvider(mode));
      final catalogue =
          ref.watch(assetsProvider).valueOrNull ?? const <MarketAsset>[];
      MarketAsset? assetFor(String id) =>
          catalogue.where((item) => item.id == id).firstOrNull;
      final wallet = accounts.value
          ?.where((account) => account.mode == mode)
          .firstOrNull
          ?.wallets
          .firstOrNull;
      return Column(children: [
        PrimeVestHeader(
          title: 'Portfolio',
          subtitle: mode == AccountMode.real
              ? 'Your virtual balance and trades'
              : 'Your practice balance and trades',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            Expanded(
                child: MiniStat(
                    label: 'Available',
                    value: '\$${wallet?.available ?? '—'}')),
            Expanded(
                child: MiniStat(
                    label: 'Locked', value: '\$${wallet?.locked ?? '—'}')),
          ]),
        ),
        const SizedBox(height: 12),
        timedContracts.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
          data: (items) => items.isEmpty
              ? const SizedBox.shrink()
              : SizedBox(
                  height: 224,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    scrollDirection: Axis.horizontal,
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (_, index) {
                      final contract = items[index];
                      final payout =
                          double.tryParse(contract.payoutAmount ?? '');
                      final stake = double.tryParse(contract.investmentAmount);
                      final settledPnl = payout != null && stake != null
                          ? payout - stake
                          : null;
                      final pnlLabel = settledPnl == null
                          ? ''
                          : ' • P/L ${settledPnl > 0 ? '+' : settledPnl < 0 ? '-' : ''}\$${settledPnl.abs().toStringAsFixed(2)}';
                      return SizedBox(
                        width: 260,
                        child: ActivityCard(
                          asset: assetFor(contract.instrumentId),
                          title: contract.instrumentId.toUpperCase(),
                          badge: '${contract.direction} • ${contract.result}',
                          value: contract.result == 'PENDING'
                              ? contractTimeRemaining(contract.expiryTimestamp)
                              : 'Returned \$${contract.payoutAmount ?? '—'}',
                          positive: contract.result == 'WIN',
                          subtitle:
                              'Stake \$${contract.investmentAmount}$pnlLabel • Fee \$${contract.feeAmount ?? '0.00'}',
                        ),
                      );
                    },
                  ),
                ),
        ),
        Expanded(
          child: positions.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => EmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Could not load portfolio',
              body: error is ApiFailure ? error.message : error.toString(),
            ),
            data: (items) => items.isEmpty
                ? const EmptyState(
                    icon: Icons.layers_clear_outlined,
                    title: 'No open positions',
                    body: 'Your open positions will appear here after a trade.',
                  )
                : RefreshIndicator(
                    onRefresh: () async {
                      ref.invalidate(positionsProvider(mode));
                      ref.invalidate(accountsProvider);
                    },
                    child: ListView.builder(
                      padding: const EdgeInsets.all(20),
                      itemCount: items.length,
                      itemBuilder: (_, index) {
                        final position = items[index];
                        final pnl = double.tryParse(position.status == 'OPEN'
                                ? position.unrealizedPnl
                                : position.realizedPnl) ??
                            0;
                        return ActivityCard(
                          asset: assetFor(position.instrumentId),
                          title: position.instrumentId.toUpperCase(),
                          badge: '${position.side} • ${position.status}',
                          value: '\$${pnl.toStringAsFixed(2)}',
                          positive: pnl >= 0,
                          subtitle:
                              'Entry ${position.averageEntry} • Qty ${position.quantity}',
                          action: position.status == 'OPEN'
                              ? TextButton(
                                  onPressed: () async {
                                    try {
                                      await ref
                                          .read(tradingRepositoryProvider)
                                          .closePosition(position.id);
                                      ref.invalidate(positionsProvider(mode));
                                      ref.invalidate(accountsProvider);
                                    } on ApiFailure catch (error) {
                                      if (context.mounted) {
                                        _result(context, false, error.message);
                                      }
                                    }
                                  },
                                  child: const Text('Close'),
                                )
                              : null,
                        );
                      },
                    ),
                  ),
          ),
        ),
      ]);
    }
    final account = ref.watch(demoAccountProvider);
    final assets = ref.watch(assetsProvider).value ?? const <MarketAsset>[];
    final prices = ref.watch(marketProvider).prices;
    MarketAsset? asset(String id) =>
        assets.where((item) => item.id == id).firstOrNull;
    return Column(children: [
      const PrimeVestHeader(title: 'Portfolio', subtitle: 'Your demo activity'),
      Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            Expanded(
                child: MiniStat(
                    label: 'Available',
                    value: usdFromCents(account.availablePaisa))),
            Expanded(
                child: MiniStat(
                    label: 'Locked', value: usdFromCents(account.lockedPaisa))),
          ])),
      const SizedBox(height: 14),
      Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Open')),
              ButtonSegment(value: 1, label: Text('Timed')),
              ButtonSegment(value: 2, label: Text('History'))
            ],
            selected: {tab},
            onSelectionChanged: (value) => setState(() => tab = value.first),
          )),
      const SizedBox(height: 10),
      Expanded(
          child: switch (tab) {
        0 => account.positions.isEmpty
            ? const EmptyState(
                icon: Icons.layers_clear_outlined,
                title: 'No open positions',
                body: 'Place a demo BUY or SELL trade to see it here.')
            : ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: account.positions.length,
                itemBuilder: (_, index) {
                  final position = account.positions[index];
                  final item = asset(position.assetId);
                  final price = prices[position.assetId] ?? position.entryPrice;
                  final direction = position.side == TradeSide.buy ? 1 : -1;
                  final pnl = ((price - position.entryPrice) *
                          position.quantity *
                          100 *
                          direction)
                      .round();
                  return ActivityCard(
                      asset: item,
                      title: item?.symbol ?? position.assetId,
                      badge: position.side.name.toUpperCase(),
                      value: usdFromCents(pnl),
                      positive: pnl >= 0,
                      subtitle:
                          'Entry ${position.entryPrice.toStringAsFixed(item?.precision ?? 2)} • ${usdFromCents(position.stakePaisa)}',
                      action: TextButton(
                          onPressed: () => ref
                              .read(demoAccountProvider.notifier)
                              .closePosition(position.id),
                          child: const Text('Close')));
                }),
        1 => account.contracts.isEmpty
            ? const EmptyState(
                icon: Icons.timer_outlined,
                title: 'No timed contracts',
                body: 'Start an UP or DOWN demo contract from Trade.')
            : ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: account.contracts.length,
                itemBuilder: (_, index) {
                  final contract = account.contracts[index];
                  final remaining = contract.expiryTimestamp
                      .difference(DateTime.now())
                      .inSeconds
                      .clamp(0, 9999);
                  return ActivityCard(
                      asset: asset(contract.assetId),
                      title:
                          asset(contract.assetId)?.symbol ?? contract.assetId,
                      badge: contract.direction.name.toUpperCase(),
                      value: contract.result == ContractResult.pending
                          ? '${remaining}s'
                          : contract.result.name.toUpperCase(),
                      positive: contract.result == ContractResult.win,
                      subtitle:
                          '${usdFromCents(contract.investmentPaisa)} • 82% payout');
                }),
        _ => account.history.isEmpty
            ? const EmptyState(
                icon: Icons.history,
                title: 'No closed trades',
                body: 'Closed demo positions will appear here.')
            : ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: account.history.length,
                itemBuilder: (_, index) {
                  final record = account.history[index];
                  return ActivityCard(
                      asset: asset(record.position.assetId),
                      title: asset(record.position.assetId)?.symbol ??
                          record.position.assetId,
                      badge: record.position.side.name.toUpperCase(),
                      value: usdFromCents(record.pnlPaisa),
                      positive: record.pnlPaisa >= 0,
                      subtitle: 'Closed ${timeAgo(record.closedAt)}');
                }),
      }),
    ]);
  }
}

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(demoAccountProvider);
    final mode = ref.watch(selectedAccountModeProvider);
    final session = ref.watch(sessionProvider);
    final currentUser = ref.watch(currentUserProvider).valueOrNull;
    final authenticated = session.phase == SessionPhase.authenticated;
    return Column(children: [
      PrimeVestHeader(
        title: 'Profile',
        subtitle: session.phase == SessionPhase.authenticated
            ? session.user?.email ?? 'Authenticated account'
            : 'Guest demo account',
      ),
      Expanded(
          child: ListView(padding: const EdgeInsets.all(20), children: [
        Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
                color: PrimeVestDesignSystem.surfaceDark,
                borderRadius: BorderRadius.circular(18)),
            child: Row(children: [
              ProfileAvatar(user: currentUser),
              const SizedBox(width: 14),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(currentUser?.profile?.fullName ?? 'Zettax Investor',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 17)),
                    const SizedBox(height: 4),
                    Text(
                        authenticated
                            ? 'Zettax account • Bangladesh'
                            : 'Guest practice account • local only',
                        style: const TextStyle(
                            color: PrimeVestDesignSystem.textMuted))
                  ])),
              TextButton.icon(
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit'),
                onPressed: () {
                  if (!authenticated) {
                    context.push('/login');
                    return;
                  }
                  if (currentUser == null) {
                    showTopNotification(
                        'Profile is loading. Please try again.');
                    return;
                  }
                  Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => EditProfileScreen(user: currentUser)));
                },
              ),
            ])),
        const SizedBox(height: 18),
        if (mode == AccountMode.demo && !authenticated)
          ProfileTile(
              icon: Icons.receipt_long_outlined,
              title: 'Demo transactions',
              subtitle:
                  '${account.transactions.length} virtual balance entries',
              onTap: () => context.push('/transactions')),
        if (mode == AccountMode.demo && authenticated)
          const ProfileTile(
            icon: Icons.receipt_long_outlined,
            title: 'Demo transactions',
            subtitle: 'History view is unavailable in this build',
          ),
        if (mode == AccountMode.real) ...[
          ProfileTile(
            icon: Icons.add_card,
            title: 'Deposit',
            subtitle: 'bKash, Nagad or Rocket',
            onTap: () => context.push(authenticated ? '/cash-in' : '/login'),
          ),
          ProfileTile(
            icon: Icons.account_balance_wallet_outlined,
            title: 'Withdraw',
            subtitle: 'Request payout to your mobile wallet',
            onTap: () => context.push(authenticated ? '/withdraw' : '/login'),
          ),
        ],
        ProfileTile(
            icon: Icons.shield_outlined,
            title: 'Security',
            subtitle: 'Password and signed-in devices',
            onTap: () => context.push('/security')),
        ProfileTile(
            icon: Icons.forum_outlined,
            title: 'Community',
            subtitle: 'Market ideas, images and conversation',
            onTap: () => context.push('/community')),
        ProfileTile(
            icon: Icons.auto_graph_outlined,
            title: 'Prediction',
            subtitle: 'Create questions and vote on market outcomes',
            onTap: () => context.push('/prediction')),
        ProfileTile(
            icon: Icons.translate,
            title: 'Language',
            subtitle: 'English • বাংলা',
            onTap: () => context.push('/language')),
        ProfileTile(
            icon: Icons.help_outline,
            title: 'Help & education',
            subtitle: 'Learn how trading and settlement work',
            onTap: () => context.push('/education')),
        ProfileTile(
            icon: Icons.gavel_outlined,
            title: 'Risk disclosure',
            subtitle: 'Trading involves risk',
            onTap: () => context.push('/risk')),
        const SizedBox(height: 18),
        OutlinedButton.icon(
            onPressed: mode == AccountMode.demo && !authenticated
                ? () => _confirmReset(context, ref)
                : null,
            icon: const Icon(Icons.restart_alt),
            label: Text(authenticated
                ? 'Demo reset unavailable in this build'
                : 'Reset guest demo account')),
        if (session.phase == SessionPhase.authenticated) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () async {
              await ref.read(sessionProvider.notifier).logout();
              if (context.mounted) context.go('/welcome');
            },
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
          ),
        ],
        const SizedBox(height: 10),
        const Center(
            child: Text('Virtual funds cannot be withdrawn or transferred.',
                style: TextStyle(
                    color: PrimeVestDesignSystem.textMuted, fontSize: 11))),
      ])),
    ]);
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Reset demo account?'),
              content: const Text(
                  'This clears all demo positions and restores your virtual balance to \$1,000.00.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Reset'))
              ],
            ));
    if (approved == true) ref.read(demoAccountProvider.notifier).reset();
  }
}

void _result(BuildContext context, bool ok, String message) {
  showTopNotification(message, success: ok);
}

class _ActiveTradeItem {
  const _ActiveTradeItem({
    required this.id,
    required this.assetId,
    required this.title,
    required this.detail,
    required this.value,
    required this.positive,
    this.onClose,
  });
  final String id;
  final String assetId;
  final String title;
  final String detail;
  final String value;
  final bool positive;
  final VoidCallback? onClose;
}

class _ActiveTradesStrip extends StatelessWidget {
  const _ActiveTradesStrip({required this.items, required this.onSelect});
  final List<_ActiveTradeItem> items;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => Column(
        key: const ValueKey('active-trades-strip'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(children: [
              const Icon(Icons.layers_outlined,
                  size: 15, color: PrimeVestDesignSystem.primaryGold),
              const SizedBox(width: 5),
              Text('Open trades (${items.length})',
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w800)),
              if (items.isEmpty) ...[
                const SizedBox(width: 8),
                const Text('None yet',
                    style: TextStyle(
                        color: PrimeVestDesignSystem.textMuted, fontSize: 10)),
              ],
            ]),
          ),
          if (items.isNotEmpty) ...[
            const SizedBox(height: 5),
            SizedBox(
              height: 78,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 5),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 7),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return InkWell(
                    key: ValueKey('open-trade-${item.id}'),
                    borderRadius: BorderRadius.circular(11),
                    onTap: () => onSelect(item.assetId),
                    child: Container(
                      width: 236,
                      padding: const EdgeInsets.fromLTRB(10, 6, 7, 5),
                      decoration: BoxDecoration(
                        color: PrimeVestDesignSystem.surfaceDark,
                        border: Border.all(color: const Color(0xFF514537)),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Expanded(
                                  child: Text(item.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800))),
                              Text(item.value,
                                  maxLines: 1,
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: item.positive
                                          ? PrimeVestDesignSystem.positive
                                          : PrimeVestDesignSystem.negative)),
                            ]),
                            const SizedBox(height: 2),
                            Row(children: [
                              Expanded(
                                  child: Text(item.detail,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 9,
                                          color: PrimeVestDesignSystem
                                              .textMuted))),
                              if (item.onClose != null)
                                TextButton(
                                    onPressed: item.onClose,
                                    style: TextButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 4),
                                        minimumSize: const Size(0, 22)),
                                    child: const Text('Close',
                                        style: TextStyle(fontSize: 10))),
                            ]),
                          ]),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      );
}

class _TradeModeSelector extends StatelessWidget {
  const _TradeModeSelector(
      {required this.timed, required this.onChanged, this.compact = false});
  final bool timed;
  final bool compact;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
        key: const ValueKey('trade-mode-selector'),
        height: compact ? 32 : 38,
        width: double.infinity,
        child: SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: true, label: Text('Timed')),
            ButtonSegment(value: false, label: Text('No expiry')),
          ],
          selected: {timed},
          onSelectionChanged: onChanged == null
              ? null
              : (selection) => onChanged!(selection.first),
          style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              textStyle: WidgetStateProperty.all(
                  const TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
        ),
      );
}

class _DurationPresets extends StatelessWidget {
  const _DurationPresets(
      {required this.value, required this.onSelected, this.compact = false});
  final int value;
  final bool compact;
  final ValueChanged<int>? onSelected;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: compact ? 30 : 37,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          for (final (seconds, label) in [
            (60, '1m'),
            (300, '5m'),
            (600, '10m'),
            (900, '15m'),
            (3600, '1h')
          ])
            Padding(
                padding: const EdgeInsets.only(right: 5),
                child: TextButton(
                  key: ValueKey('duration-preset-$seconds'),
                  onPressed:
                      onSelected == null ? null : () => onSelected!(seconds),
                  style: TextButton.styleFrom(
                    minimumSize: Size(compact ? 38 : 42, compact ? 28 : 34),
                    padding: const EdgeInsets.symmetric(horizontal: 7),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: value == seconds
                        ? const Color(0x44F8B425)
                        : const Color(0xFF332D25),
                  ),
                  child: Text(label, style: const TextStyle(fontSize: 10)),
                )),
        ]),
      );
}

class _TradeStepper extends StatelessWidget {
  const _TradeStepper(
      {required this.label,
      required this.value,
      this.decrease,
      this.increase,
      this.onTap});
  final String label;
  final String value;
  final VoidCallback? decrease;
  final VoidCallback? increase;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
            color: PrimeVestDesignSystem.surfaceDark,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF403829))),
        child: Row(children: [
          SizedBox(
              width: 28,
              child: IconButton(
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints.tightFor(width: 28, height: 34),
                  onPressed: decrease,
                  icon: const Icon(Icons.remove, size: 16))),
          Expanded(
              child: InkWell(
                  onTap: onTap,
                  child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1),
                      child: Column(children: [
                        FittedBox(
                            child: Text(value,
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700))),
                        Text(label,
                            style: const TextStyle(
                                fontSize: 8,
                                color: PrimeVestDesignSystem.textMuted)),
                      ])))),
          SizedBox(
              width: 28,
              child: IconButton(
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints.tightFor(width: 28, height: 34),
                  onPressed: increase,
                  icon: const Icon(Icons.add, size: 16))),
        ]),
      );
}
