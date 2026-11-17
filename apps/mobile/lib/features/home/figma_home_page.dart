import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;
import 'package:url_launcher/url_launcher.dart';
import 'package:primevest_mobile/app/design_system.dart';
import 'package:primevest_mobile/app/top_notification.dart';
import 'package:primevest_mobile/core/account/account_mode_selector.dart';
import 'package:primevest_mobile/core/account/account_models.dart';
import 'package:primevest_mobile/core/app_providers.dart';
import 'package:primevest_mobile/demo/models.dart';
import 'package:primevest_mobile/demo/providers.dart';
import 'package:primevest_mobile/features/community/community_safety.dart';
import 'package:primevest_mobile/features/home/home_data.dart';
import 'package:primevest_mobile/market/market_data_providers.dart';

const _gold = PrimeVestDesignSystem.primaryGold;
const _muted = PrimeVestDesignSystem.textMuted;
const _edge = Color(0xFF40382F);
const _surface = Color(0xFF24221E);
const _positive = PrimeVestDesignSystem.positive;
const _negative = PrimeVestDesignSystem.negative;

class FigmaHomePage extends ConsumerStatefulWidget {
  const FigmaHomePage(
      {super.key,
      required this.onMarkets,
      required this.onTrade,
      required this.onPortfolio,
      required this.onProfile});
  final VoidCallback onMarkets, onTrade, onPortfolio, onProfile;
  @override
  ConsumerState<FigmaHomePage> createState() => _FigmaHomePageState();
}

class _FigmaHomePageState extends ConsumerState<FigmaHomePage> {
  bool guideVisible = true;
  Future<void> _community() async {
    ref.read(homeCommunityProvider.notifier).clear();
    await context.push('/community');
    if (mounted) ref.invalidate(homeCommunityProvider);
  }

  void _funds() =>
      context.push(ref.read(sessionProvider).phase == SessionPhase.authenticated
          ? '/cash-in'
          : '/login');
  void _sheet(String title, List<Widget> children) =>
      showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          backgroundColor: PrimeVestDesignSystem.surfaceDark,
          builder: (sheetContext) => SafeArea(
              child: SingleChildScrollView(
                  child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title,
                                style: const TextStyle(
                                    fontSize: 22, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 16),
                            ...children
                          ])))));
  void _help() => _sheet('How can we help?', [
        const Text(
            'Explore markets and learn with virtual trading. Check your account mode before placing a trade.',
            style: TextStyle(color: _muted)),
        _helpRow(Icons.search, 'Find an asset',
            'Browse markets and explore a pair', widget.onMarkets),
        _helpRow(Icons.swap_vert, 'Place a demo trade',
            'Explore the trading tools', widget.onTrade),
        _helpRow(Icons.account_balance_wallet_outlined, 'Manage assets',
            'View your balance and activity', widget.onPortfolio),
        ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.support_agent, color: _gold),
            title: const Text('Contact support'),
            subtitle: const Text('Get help from the Zettax team'),
            onTap: () => launchUrl(Uri(
                scheme: 'mailto',
                path: 'fardinhasan18@gmail.com',
                queryParameters: {'subject': 'Zettax support'}))),
      ]);
  Widget _helpRow(
          IconData icon, String title, String body, VoidCallback action) =>
      ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon, color: _gold),
          title: Text(title),
          subtitle: Text(body),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.pop(context);
            action();
          });
  void _profile() => _sheet('Your account', [
        const Row(children: [
          Expanded(child: Text('Account mode')),
          AccountModeSelector()
        ]),
        _helpRow(Icons.person_outline, 'View profile',
            'Settings, security and account tools', widget.onProfile),
        _helpRow(Icons.account_balance_wallet_outlined, 'Portfolio',
            'Your balances and positions', widget.onPortfolio),
      ]);
  void _notifications() {
    final notice = ref.read(fundingRealtimeNoticeProvider);
    _sheet('Account updates', [
      Icon(
          notice == null
              ? Icons.notifications_none
              : Icons.notifications_active_outlined,
          color: _gold,
          size: 30),
      const SizedBox(height: 14),
      Text(notice?.message ?? 'No recent account updates on this device.',
          style: const TextStyle(height: 1.5)),
    ]);
  }

  void _p2p() => _sheet('P2P trading', [
        const Text(
            'P2P offers are not available yet. You can explore markets and practice trading with virtual funds.',
            style: TextStyle(color: _muted, height: 1.5)),
        const SizedBox(height: 16),
        _GoldButton(
            label: 'Explore markets',
            onTap: () {
              Navigator.pop(context);
              widget.onMarkets();
            }),
      ]);

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final mode = ref.watch(selectedAccountModeProvider);
    final account = ref.watch(demoAccountProvider);
    final wallet = ref
        .watch(accountsProvider)
        .valueOrNull
        ?.where((a) => a.mode == mode)
        .firstOrNull
        ?.wallets
        .firstOrNull;
    final authenticated = session.phase == SessionPhase.authenticated;
    final balance = authenticated
        ? double.tryParse(wallet?.equity ?? '')
        : mode == AccountMode.demo
            ? (account.availablePaisa + account.lockedPaisa) / 100
            : null;
    final assets = ref.watch(assetsProvider);
    final popular = (assets.valueOrNull ?? const <MarketAsset>[])
        .where((a) => a.assetClass == 'Crypto')
        .take(4)
        .toList();
    final btc = popular
        .where((a) => a.symbol.toUpperCase().startsWith('BTC'))
        .firstOrNull;
    final btcSeries = btc == null
        ? null
        : ref
            .watch(liveCandlesProvider(
                (assetId: btc.id, interval: '1m', limit: 90)))
            .valueOrNull;
    final btcPrice = btcSeries != null && !btcSeries.isSyntheticOhlc
        ? btcSeries.candles.lastOrNull?.close
        : null;
    final equivalent = balance != null && btcPrice != null && btcPrice > 0
        ? balance / btcPrice
        : null;
    final profile = authenticated
        ? ref.watch(currentUserProvider).valueOrNull?.profile
        : null;
    final name = profile?.fullName.trim();
    final initials = name != null && name.isNotEmpty
        ? name
            .split(RegExp(r'\s+'))
            .take(2)
            .map((s) => s.characters.first)
            .join()
            .toUpperCase()
        : authenticated
            ? session.user!.email.characters.first.toUpperCase()
            : 'Z';
    return Theme(
        data: Theme.of(context).copyWith(
            textTheme: Theme.of(context).textTheme.apply(fontFamily: 'DMSans')),
        child: DefaultTextStyle.merge(
            style: const TextStyle(fontFamily: 'DMSans'),
            child: DecoratedBox(
                decoration: const BoxDecoration(
                    gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                      Color(0xFF2C281F),
                      PrimeVestDesignSystem.backgroundDark,
                      PrimeVestDesignSystem.backgroundDark
                    ],
                        stops: [
                      0,
                      .32,
                      1
                    ])),
                child: SafeArea(
                    bottom: false,
                    child: RefreshIndicator(
                        color: _gold,
                        onRefresh: () async {
                          ref.invalidate(homeSentimentProvider);
                          ref.invalidate(accountsProvider);
                          ref.invalidate(assetsProvider);
                          ref.invalidate(homeCommunityProvider);
                          for (final asset in popular) {
                            ref.invalidate(liveCandlesProvider((
                              assetId: asset.id,
                              interval: '1m',
                              limit: 90
                            )));
                          }
                        },
                        child: ListView(
                            padding: const EdgeInsets.fromLTRB(14, 18, 14, 28),
                            children: [
                              Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Expanded(
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                          _Eyebrow('TRADING TERMINAL'),
                                          SizedBox(height: 5),
                                          Text('Home',
                                              style: TextStyle(
                                                  fontFamily: 'Manrope',
                                                  fontSize: 22,
                                                  height: 1.5,
                                                  fontWeight: FontWeight.w600)),
                                        ])),
                                    _HeaderControl(
                                        label: 'Help and guidance',
                                        onTap: _help,
                                        child: const Text('?',
                                            style: TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.w800,
                                                color: _gold))),
                                    const SizedBox(width: 8),
                                    _HeaderControl(
                                        label: 'Account updates',
                                        onTap: _notifications,
                                        child: const Icon(
                                            Icons.notifications_none_rounded,
                                            size: 21)),
                                    const SizedBox(width: 8),
                                    _HeaderControl(
                                        label: 'Profile and account mode',
                                        onTap: _profile,
                                        child: Container(
                                            padding: const EdgeInsets.all(5),
                                            decoration: BoxDecoration(
                                                color: _gold.withValues(
                                                    alpha: .10),
                                                borderRadius:
                                                    BorderRadius.circular(7)),
                                            child: Text(initials,
                                                style: const TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w700,
                                                    color: _gold)))),
                                  ]),
                              const SizedBox(height: 21),
                              _HomePanel(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 22, vertical: 18),
                                  glow: true,
                                  child:
                                      LayoutBuilder(builder: (context, bounds) {
                                    final details = Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text('Overall balance',
                                              style: TextStyle(
                                                  color: _muted,
                                                  fontSize: 9,
                                                  height: 1.5)),
                                          const SizedBox(height: 2),
                                          Wrap(
                                              crossAxisAlignment:
                                                  WrapCrossAlignment.end,
                                              spacing: 8,
                                              runSpacing: 4,
                                              children: [
                                                Text(
                                                    balance == null ||
                                                            !balance.isFinite
                                                        ? '—'
                                                        : NumberFormat.currency(
                                                                symbol: '\$',
                                                                decimalDigits:
                                                                    2)
                                                            .format(balance),
                                                    style: const TextStyle(
                                                        fontFamily: 'Manrope',
                                                        fontSize: 24,
                                                        height: 1.35,
                                                        fontWeight:
                                                            FontWeight.w700)),
                                                Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                            bottom: 3),
                                                    child: Text(
                                                        equivalent == null
                                                            ? '≈ — BTC'
                                                            : '≈ ${equivalent.toStringAsFixed(4)} BTC',
                                                        style: const TextStyle(
                                                            color: _muted,
                                                            fontSize: 8))),
                                              ]),
                                        ]);
                                    final button = _GoldButton(
                                        label: '＋ Add funds', onTap: _funds);
                                    return bounds.maxWidth < 275 ||
                                            MediaQuery.textScalerOf(context)
                                                    .scale(1) >
                                                1.3
                                        ? Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                                details,
                                                const SizedBox(height: 12),
                                                button
                                              ])
                                        : Row(children: [
                                            Expanded(child: details),
                                            const SizedBox(width: 10),
                                            button
                                          ]);
                                  })),
                              if (guideVisible) ...[
                                const SizedBox(height: 15),
                                _HomePanel(
                                    padding: const EdgeInsets.fromLTRB(
                                        16, 12, 10, 12),
                                    child: Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          Padding(
                                              padding: const EdgeInsets.only(
                                                  right: 22),
                                              child: LayoutBuilder(
                                                  builder: (context, bounds) {
                                                final step = Row(children: [
                                                  Container(
                                                      width: 23,
                                                      height: 23,
                                                      alignment:
                                                          Alignment.center,
                                                      decoration: BoxDecoration(
                                                          shape:
                                                              BoxShape.circle,
                                                          color:
                                                              _gold.withValues(
                                                                  alpha: .12)),
                                                      child: const Text('1',
                                                          style: TextStyle(
                                                              fontSize: 10,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w800,
                                                              color: _gold))),
                                                  const SizedBox(width: 8),
                                                  const Expanded(
                                                      child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                        Text('Add funds',
                                                            style: TextStyle(
                                                                fontSize: 10,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700)),
                                                        SizedBox(height: 2),
                                                        Text(
                                                            'Top up your demo wallet',
                                                            style: TextStyle(
                                                                fontSize: 8,
                                                                color: _muted,
                                                                height: 1.5)),
                                                      ]))
                                                ]);
                                                final start = _GoldButton(
                                                    label: 'Get started',
                                                    onTap: widget.onMarkets,
                                                    compact: true);
                                                return bounds.maxWidth < 260 ||
                                                        MediaQuery.textScalerOf(
                                                                    context)
                                                                .scale(1) >
                                                            1.3
                                                    ? Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                            step,
                                                            const SizedBox(
                                                                height: 10),
                                                            start
                                                          ])
                                                    : Row(children: [
                                                        Expanded(
                                                            flex: 5,
                                                            child: step),
                                                        const SizedBox(
                                                            width: 8),
                                                        const Expanded(
                                                            flex: 5,
                                                            child: Text(
                                                                'Three guided steps to your first demo trade',
                                                                style: TextStyle(
                                                                    color:
                                                                        _muted,
                                                                    fontSize: 8,
                                                                    height:
                                                                        1.5))),
                                                        const SizedBox(
                                                            width: 8),
                                                        start
                                                      ]);
                                              })),
                                          Positioned(
                                              top: -11,
                                              right: -7,
                                              child: IconButton(
                                                  tooltip:
                                                      'Dismiss getting started guide',
                                                  constraints:
                                                      const BoxConstraints
                                                          .tightFor(
                                                          width: 28,
                                                          height: 28),
                                                  padding: EdgeInsets.zero,
                                                  onPressed: () => setState(
                                                      () =>
                                                          guideVisible = false),
                                                  icon: const Icon(Icons.close,
                                                      size: 13,
                                                      color: _muted))),
                                        ])),
                              ],
                              const SizedBox(height: 15),
                              const _SentimentCard(),
                              const SizedBox(height: 15),
                              _HomePanel(
                                  padding: const EdgeInsets.all(18),
                                  child: Column(children: [
                                    _SectionHeading(
                                        eyebrow: 'P2P TODAY',
                                        title: 'Best verified offers',
                                        action: 'View P2P',
                                        onTap: _p2p),
                                    for (final row in [
                                      ('Buy', 'USDT'),
                                      ('Sell', 'USDT'),
                                      ('Buy', 'BTC')
                                    ]) ...[
                                      const Divider(height: 1, color: _edge),
                                      InkWell(
                                          onTap: _p2p,
                                          child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 12),
                                              child: Row(children: [
                                                SizedBox(
                                                    width: 42,
                                                    child: Text(row.$1,
                                                        style: TextStyle(
                                                            fontSize: 11,
                                                            color: row.$1 ==
                                                                    'Buy'
                                                                ? _positive
                                                                : _negative))),
                                                Expanded(
                                                    child: Text(row.$2,
                                                        style: const TextStyle(
                                                            fontSize: 11,
                                                            fontWeight:
                                                                FontWeight
                                                                    .w700))),
                                                const Text('—',
                                                    style: TextStyle(
                                                        color: _muted,
                                                        fontSize: 11)),
                                                const SizedBox(width: 25),
                                                const Icon(Icons.chevron_right,
                                                    size: 15),
                                              ]))),
                                    ],
                                    const Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                            'Verified offers are not available yet.',
                                            style: TextStyle(
                                                color: _muted, fontSize: 9))),
                                  ])),
                              const SizedBox(height: 24),
                              _SectionHeading(
                                  eyebrow: 'MARKETS',
                                  title: 'Popular today',
                                  action: 'All markets',
                                  onTap: widget.onMarkets),
                              const SizedBox(height: 10),
                              if (popular.isNotEmpty)
                                _PopularGrid(assets: popular)
                              else
                                _HomePanel(
                                    child: Text(
                                        assets.isLoading
                                            ? 'Loading market prices…'
                                            : 'Markets are unavailable. Pull down to retry.',
                                        style: const TextStyle(
                                            color: _muted, fontSize: 12))),
                              if (popular.isNotEmpty)
                                const Padding(
                                    padding: EdgeInsets.only(top: 6),
                                    child: Text(
                                        'Recent price movement · 1 min candles',
                                        style: TextStyle(
                                            color: _muted, fontSize: 9))),
                              const SizedBox(height: 24),
                              _SectionHeading(
                                  eyebrow: 'COMMUNITY PULSE',
                                  title: 'What people are discussing',
                                  action: 'Open community',
                                  onTap: _community),
                              const SizedBox(height: 10),
                              _CommunityPreview(onOpen: _community),
                            ]))))));
  }
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Text(label,
      style: const TextStyle(
          fontFamily: 'DMSans',
          fontSize: 10,
          height: 1.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
          color: _muted));
}

class _HomePanel extends StatelessWidget {
  const _HomePanel(
      {required this.child,
      this.padding = const EdgeInsets.all(22),
      this.glow = false});
  final Widget child;
  final EdgeInsets padding;
  final bool glow;
  @override
  Widget build(BuildContext context) => Container(
      padding: padding,
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: _edge),
          gradient: LinearGradient(
              begin: glow ? Alignment.topRight : Alignment.topLeft,
              end: Alignment.bottomLeft,
              colors: glow
                  ? const [Color(0xFF3B3020), _surface]
                  : const [Color(0xFF2B2822), Color(0xFF211F1C)])),
      child: child);
}

class _GoldButton extends StatelessWidget {
  const _GoldButton(
      {required this.label, required this.onTap, this.compact = false});
  final String label;
  final VoidCallback onTap;
  final bool compact;
  @override
  Widget build(BuildContext context) => FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(
          backgroundColor: _gold,
          foregroundColor: const Color(0xFF1A160E),
          minimumSize: Size(0, compact ? 32 : 35),
          padding:
              EdgeInsets.symmetric(horizontal: compact ? 11 : 14, vertical: 10),
          tapTargetSize: MaterialTapTargetSize.padded,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(
              fontFamily: 'DMSans', fontSize: 10, fontWeight: FontWeight.w700)),
      child: Text(label));
}

class _HeaderControl extends StatelessWidget {
  const _HeaderControl(
      {required this.label, required this.onTap, required this.child});
  final String label;
  final VoidCallback onTap;
  final Widget child;
  @override
  Widget build(BuildContext context) => Semantics(
      button: true,
      label: label,
      child: Tooltip(
          message: label,
          child: SizedBox(
              width: 40,
              height: 44,
              child: Center(
                  child: Material(
                      color: _surface,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(9),
                          side: const BorderSide(color: _edge)),
                      child: InkWell(
                          onTap: onTap,
                          borderRadius: BorderRadius.circular(9),
                          child: SizedBox(
                              width: 35,
                              height: 35,
                              child: Center(child: child))))))));
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(
      {required this.eyebrow,
      required this.title,
      required this.action,
      required this.onTap});
  final String eyebrow, title, action;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, bounds) {
        final label =
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _Eyebrow(eyebrow),
          const SizedBox(height: 3),
          Text(title,
              style: const TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 16,
                  height: 1.5,
                  fontWeight: FontWeight.w600))
        ]);
        final button = TextButton(
            onPressed: onTap,
            style: TextButton.styleFrom(
                foregroundColor: _gold,
                minimumSize: const Size(0, 44),
                padding: EdgeInsets.zero,
                textStyle: const TextStyle(fontFamily: 'DMSans', fontSize: 11)),
            child: Text(action));
        return bounds.maxWidth < 240 ||
                MediaQuery.textScalerOf(context).scale(1) > 1.3
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [label, button])
            : Row(children: [
                Expanded(child: label),
                const SizedBox(width: 12),
                button
              ]);
      });
}

class _SentimentCard extends ConsumerWidget {
  const _SentimentCard();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final response = ref.watch(homeSentimentProvider);
    final data = response.valueOrNull;
    final summary =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _Eyebrow('MARKET SENTIMENT'),
      const SizedBox(height: 8),
      const Text('Fear & Greed Index',
          style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 16,
              height: 1.5,
              fontWeight: FontWeight.w600)),
      Text(data?.value.toString() ?? '—',
          style: const TextStyle(
              fontFamily: 'Manrope',
              fontSize: 36,
              height: 1.35,
              fontWeight: FontWeight.w800,
              color: _gold)),
      Text(
          data?.classification ??
              (response.isLoading ? 'Loading…' : 'Unavailable'),
          style: const TextStyle(fontSize: 11, color: _gold)),
      const SizedBox(height: 11),
      Text(
          'Yesterday ${data?.yesterday ?? '—'} · Last week ${data?.lastWeek ?? '—'}',
          style: const TextStyle(fontSize: 8, color: _muted)),
    ]);
    return _HomePanel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      LayoutBuilder(builder: (context, bounds) {
        final gaugeWidth = math.min(148.0, bounds.maxWidth * .45);
        final gauge = Semantics(
            label: data == null
                ? 'Sentiment index unavailable'
                : '${data.value} out of 100, ${data.classification}',
            child: SizedBox(
                width: gaugeWidth,
                height: 82 * gaugeWidth / 148,
                child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: data?.value.toDouble() ?? 0),
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 400),
                    curve: Curves.easeOutCubic,
                    builder: (_, value, __) => CustomPaint(
                        painter:
                            _SentimentGauge(data == null ? null : value)))));
        return bounds.maxWidth < 250 ||
                MediaQuery.textScalerOf(context).scale(1) > 1.3
            ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                summary,
                const SizedBox(height: 15),
                Center(child: gauge)
              ])
            : Row(children: [
                Expanded(child: summary),
                const SizedBox(width: 6),
                gauge
              ]);
      }),
      const SizedBox(height: 6),
      const Text(
          'A daily snapshot of Bitcoin sentiment. Prices can still move sharply.',
          style: TextStyle(fontSize: 10, height: 1.5, color: _muted)),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(
            child: Text(
                'Source: Alternative.me${data == null ? '' : ' · ${DateFormat('dd MMM').format(data.updatedAt)}'}',
                style: const TextStyle(color: _muted, fontSize: 9))),
        if (response.hasError)
          IconButton(
              tooltip: 'Retry sentiment data',
              onPressed: () => ref.invalidate(homeSentimentProvider),
              icon: const Icon(Icons.refresh, size: 17, color: _gold))
      ]),
    ]));
  }
}

class _SentimentGauge extends CustomPainter {
  const _SentimentGauge(this.value);
  final double? value;
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height - 7);
    final radius = math.min(size.width / 2 - 9, size.height - 16);
    final rect = Rect.fromCircle(center: center, radius: radius);
    final colors = value == null
        ? const [_edge, _edge, _edge]
        : const [_negative, _gold, _positive];
    for (var step = 0; step < 100; step++) {
      final f = step / 99;
      final color = f < .5
          ? Color.lerp(colors[0], colors[1], f * 2)!
          : Color.lerp(colors[1], colors[2], (f - .5) * 2)!;
      canvas.drawArc(
          rect,
          math.pi + step / 100 * math.pi,
          math.pi / 100 + .01,
          false,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 15);
    }
    if (value != null) {
      final angle = math.pi + value!.clamp(0, 100) / 100 * math.pi;
      canvas.drawLine(
          center,
          center + Offset(math.cos(angle), math.sin(angle)) * (radius - 14),
          Paint()
            ..color = _gold
            ..strokeWidth = 2);
    }
    for (final item in [('0', 1.0), ('100', size.width - 20)]) {
      final text = TextPainter(
          text: TextSpan(
              text: item.$1,
              style: const TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 8,
                  color: Colors.white,
                  fontWeight: FontWeight.w700)),
          textDirection: TextDirection.ltr)
        ..layout();
      text.paint(canvas, Offset(item.$2, size.height - 13));
    }
  }

  @override
  bool shouldRepaint(covariant _SentimentGauge old) => old.value != value;
}

class _PopularGrid extends StatelessWidget {
  const _PopularGrid({required this.assets});
  final List<MarketAsset> assets;
  @override
  Widget build(BuildContext context) => _HomePanel(
      padding: EdgeInsets.zero,
      child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: LayoutBuilder(
              builder: (context, bounds) => Column(children: [
                    for (var row = 0; row < (assets.length / 2).ceil(); row++)
                      Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (var col = 0; col < 2; col++)
                              Expanded(
                                  child: row * 2 + col < assets.length
                                      ? Container(
                                          decoration: BoxDecoration(
                                              border: Border(
                                                  top: row > 0
                                                      ? const BorderSide(
                                                          color: _edge)
                                                      : BorderSide.none,
                                                  left: col > 0
                                                      ? const BorderSide(
                                                          color: _edge)
                                                      : BorderSide.none)),
                                          child: _PopularAsset(
                                              asset: assets[row * 2 + col]))
                                      : const SizedBox.shrink()),
                          ]),
                  ]))));
}

class _PopularAsset extends ConsumerWidget {
  const _PopularAsset({required this.asset});
  final MarketAsset asset;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final series = ref
        .watch(
            liveCandlesProvider((assetId: asset.id, interval: '1m', limit: 90)))
        .valueOrNull;
    final prices = series != null && !series.isSyntheticOhlc
        ? series.candles
            .map((c) => c.close)
            .where((p) => p.isFinite && p > 0)
            .toList()
        : <double>[];
    final change = prices.length > 1
        ? (prices.last - prices.first) / prices.first * 100
        : null;
    final color = change == null || change >= 0 ? _positive : _negative;
    return InkWell(
        onTap: () => context.push('/asset/${asset.id}'),
        child: Padding(
            padding: const EdgeInsets.all(17),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              LayoutBuilder(builder: (context, bounds) {
                final label = Text(asset.symbol.split('/').first,
                    style: const TextStyle(fontSize: 11));
                final price = Text(
                    prices.isEmpty
                        ? '—'
                        : NumberFormat.currency(
                                symbol: '\$',
                                decimalDigits: asset.precision.clamp(0, 6))
                            .format(prices.last),
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700));
                return bounds.maxWidth < 130 ||
                        MediaQuery.textScalerOf(context).scale(1) > 1.3
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [label, const SizedBox(height: 3), price])
                    : Row(children: [
                        label,
                        const Spacer(),
                        Flexible(flex: 4, child: price)
                      ]);
              }),
              Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                      change == null
                          ? '—'
                          : '${change >= 0 ? '+' : ''}${change.toStringAsFixed(2)}%',
                      style: TextStyle(color: color, fontSize: 9))),
              const SizedBox(height: 5),
              Semantics(
                  label: 'Price movement over loaded one-minute candles',
                  child: SizedBox(
                      height: 32,
                      width: double.infinity,
                      child: CustomPaint(painter: _Sparkline(prices, color)))),
            ])));
  }
}

class _Sparkline extends CustomPainter {
  const _Sparkline(this.prices, this.color);
  final List<double> prices;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    if (prices.length < 2) {
      canvas.drawLine(Offset(0, size.height / 2),
          Offset(size.width, size.height / 2), Paint()..color = _edge);
      return;
    }
    final min = prices.reduce(math.min),
        max = prices.reduce(math.max),
        range = max - min;
    final points = List.generate(
        prices.length,
        (i) => Offset(
            2 + i / (prices.length - 1) * (size.width - 4),
            range == 0
                ? size.height / 2
                : size.height -
                    3 -
                    (prices[i] - min) / range * (size.height - 6)));
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(covariant _Sparkline old) =>
      old.prices != prices || old.color != color;
}

class _CommunityPreview extends ConsumerWidget {
  const _CommunityPreview({required this.onOpen});
  final Future<void> Function() onOpen;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn =
        ref.watch(sessionProvider).phase == SessionPhase.authenticated;
    final feed = ref.watch(homeCommunityProvider);
    return feed.when(
      skipLoadingOnRefresh: false,
      loading: () => const _HomePanel(
          child: Text('Loading discussions…',
              style: TextStyle(color: _muted, fontSize: 12))),
      error: (_, __) => _HomePanel(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Discussions are unavailable right now.',
            style: TextStyle(color: _muted, fontSize: 12)),
        TextButton(
            onPressed: () =>
                ref.read(homeCommunityProvider.notifier).refresh(clear: true),
            child: const Text('Try again')),
      ])),
      data: (posts) => posts.isEmpty
          ? _HomePanel(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  Text(
                      signedIn
                          ? 'Be the first to start a discussion.'
                          : 'Sign in to see community discussions.',
                      style: const TextStyle(color: _muted, fontSize: 12)),
                  TextButton(
                      onPressed: () =>
                          signedIn ? onOpen() : context.push('/login'),
                      child: Text(signedIn ? 'Open community' : 'Sign in')),
                ]))
          : Column(children: [
              for (final post in posts)
                Padding(
                    padding: const EdgeInsets.only(bottom: 15),
                    child: _PostPreview(post: post, onOpen: onOpen))
            ]),
    );
  }
}

class _PostPreview extends ConsumerStatefulWidget {
  const _PostPreview({required this.post, required this.onOpen});
  final HomeCommunityPost post;
  final Future<void> Function() onOpen;
  @override
  ConsumerState<_PostPreview> createState() => _PostPreviewState();
}

class _PostPreviewState extends ConsumerState<_PostPreview> {
  bool reacting = false;
  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final name = post.author.trim().isEmpty ? 'Zettax member' : post.author;
    final initials = name
        .split(RegExp(r'\s+'))
        .take(2)
        .map((s) => s.characters.first)
        .join()
        .toUpperCase();
    final age = post.createdAt == null
        ? null
        : DateTime.now().difference(post.createdAt!);
    final time = age == null || age.isNegative
        ? 'Recent'
        : age.inDays > 0
            ? '${age.inDays}d'
            : age.inHours > 0
                ? '${age.inHours}h'
                : '${age.inMinutes}m';
    return _HomePanel(
        padding: const EdgeInsets.all(17),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                width: 29,
                height: 29,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _gold.withValues(alpha: .12),
                    border: Border.all(color: _edge)),
                child: Text(initials,
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: _gold))),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700)),
                  Text('Community · $time',
                      style: const TextStyle(color: _muted, fontSize: 8)),
                ])),
            SizedBox(
                width: 28,
                child: CommunitySafetyMenu(
                    targetType: 'POST',
                    targetId: post.id,
                    onChanged: () => ref
                        .read(homeCommunityProvider.notifier)
                        .refresh(clear: true))),
          ]),
          const SizedBox(height: 10),
          Text(
              post.text.isEmpty
                  ? 'Shared an image. Open the discussion to view it.'
                  : post.text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, height: 1.5)),
          const SizedBox(height: 8),
          Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 15,
              children: [
                TextButton(
                    onPressed: reacting
                        ? null
                        : () async {
                            setState(() => reacting = true);
                            try {
                              await ref
                                  .read(homeCommunityProvider.notifier)
                                  .react(post);
                            } catch (_) {
                              showTopNotification(
                                  'Your reaction could not be saved. Please try again.',
                                  success: false);
                            } finally {
                              if (mounted) setState(() => reacting = false);
                            }
                          },
                    style: TextButton.styleFrom(
                        foregroundColor: post.liked ? _gold : _muted,
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(40, 40)),
                    child: Text('${post.liked ? '♥' : '♡'} ${post.likes}',
                        style: const TextStyle(fontSize: 10))),
                TextButton(
                    onPressed: widget.onOpen,
                    style: TextButton.styleFrom(
                        foregroundColor: _gold,
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 40)),
                    child: const Text('Join discussion →',
                        style: TextStyle(fontSize: 9))),
              ]),
        ]));
  }
}

class FigmaHomeNavigation extends StatelessWidget {
  const FigmaHomeNavigation(
      {super.key,
      required this.onSelected,
      required this.labels,
      this.selectedIndex = 0});
  final ValueChanged<int> onSelected;
  final List<String> labels;
  final int selectedIndex;
  @override
  Widget build(BuildContext context) => Material(
      color: const Color(0xFF211F1D),
      child: SafeArea(
          top: false,
          child: Container(
              height: 67 +
                  (MediaQuery.textScalerOf(context).scale(1) - 1).clamp(0, 2) *
                      35,
              decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: _edge))),
              child: Row(children: [
                for (var i = 0; i < labels.length; i++)
                  Expanded(
                      child: InkWell(
                          onTap: () => onSelected(i),
                          child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                    [
                                      Icons.home_outlined,
                                      Icons.bar_chart_outlined,
                                      Icons.swap_vert,
                                      Icons.account_balance_wallet_outlined,
                                      Icons.person_outline
                                    ][i],
                                    color: i == selectedIndex ? _gold : _muted,
                                    size: 21),
                                const SizedBox(height: 5),
                                Text(labels[i],
                                    style: TextStyle(
                                        fontFamily: 'DMSans',
                                        color:
                                            i == selectedIndex ? _gold : _muted,
                                        fontSize: 9)),
                              ]))),
              ]))));
}
