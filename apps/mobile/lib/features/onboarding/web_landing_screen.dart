import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:primevest_mobile/app/brand_logo.dart';
import 'package:primevest_mobile/app/design_system.dart';
import 'package:primevest_mobile/features/shared/live_trade_chart.dart';
import 'package:primevest_mobile/market/market_data_providers.dart';
import 'package:url_launcher/url_launcher.dart';

const _gold = PrimeVestDesignSystem.primaryGold;
const _muted = PrimeVestDesignSystem.textMuted;
const _downloadUrl =
    'https://play.google.com/store/apps/details?id=com.primevest.app';

class WebLandingScreen extends StatelessWidget {
  const WebLandingScreen({super.key});

  void _trade(BuildContext context) => context.go('/home?tab=2');

  Future<void> _download() => launchUrl(Uri.parse(_downloadUrl));

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 800;
    final inset = compact ? 20.0 : 48.0;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Container(
            height: compact ? 68 : 82,
            padding: EdgeInsets.symmetric(horizontal: inset),
            decoration: const BoxDecoration(
              color: Color(0xFF211F1D),
              border: Border(bottom: BorderSide(color: Color(0xFF3D352B))),
            ),
            child: Row(children: [
              const ZettaxMark(height: 34),
              const SizedBox(width: 10),
              const Text('Zettax',
                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
              const Spacer(),
              if (!compact) ...[
                TextButton(
                    onPressed: () => context.push('/education'),
                    child: const Text('Learn')),
                const SizedBox(width: 10),
                TextButton(
                    onPressed: () => context.push('/login'),
                    child: const Text('Sign in')),
                const SizedBox(width: 12),
              ],
              FilledButton.icon(
                onPressed: () => _trade(context),
                icon: const Icon(Icons.arrow_outward, size: 17),
                label: Text(compact ? 'Trade' : 'Try demo trading'),
                style: FilledButton.styleFrom(
                  minimumSize: Size(0, compact ? 40 : 44),
                  padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 20),
                ),
              ),
            ]),
          ),
          Expanded(
            child: ListView(children: [
              _LandingHero(
                compact: compact,
                inset: inset,
                onTrade: () => _trade(context),
                onDownload: _download,
              ),
              _MarketBand(compact: compact, inset: inset),
              _LivePreview(
                  compact: compact,
                  inset: inset,
                  onTrade: () => _trade(context)),
              _MarketsShowcase(
                  compact: compact,
                  inset: inset,
                  onTrade: () => _trade(context)),
              _FeatureSection(compact: compact, inset: inset),
              _StepsSection(compact: compact, inset: inset),
              _FaqSection(compact: compact, inset: inset),
              _DownloadSection(
                  compact: compact,
                  inset: inset,
                  onTrade: () => _trade(context),
                  onDownload: _download),
              _LandingFooter(
                compact: compact,
                inset: inset,
                onTrade: () => _trade(context),
                onDownload: _download,
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _LandingHero extends StatelessWidget {
  const _LandingHero({
    required this.compact,
    required this.inset,
    required this.onTrade,
    required this.onDownload,
  });

  final bool compact;
  final double inset;
  final VoidCallback onTrade;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final stacked = MediaQuery.sizeOf(context).width < 1050;
    final copy =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _Entrance(child: _Eyebrow('THE MARKET IS YOURS TO EXPLORE')),
      const SizedBox(height: 22),
      _Entrance(
        child: Text.rich(
          TextSpan(children: [
            const TextSpan(text: 'Make your next\n'),
            TextSpan(
                text: 'move a smarter one.',
                style: const TextStyle(color: _gold)),
          ]),
          style: TextStyle(
            fontSize: compact ? 43 : 68,
            height: 1.05,
            letterSpacing: -2.2,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      const SizedBox(height: 24),
      const _Entrance(
        child: Text(
          'A market workspace built for curiosity. Watch price action, explore the chart and find your rhythm with virtual demo funds—on web and Android.',
          style: TextStyle(color: _muted, fontSize: 17, height: 1.55),
        ),
      ),
      const SizedBox(height: 28),
      Wrap(spacing: 12, runSpacing: 12, children: [
        FilledButton.icon(
          onPressed: onTrade,
          icon: const Icon(Icons.arrow_outward),
          label: const Text('Start demo trading'),
          style: FilledButton.styleFrom(
              minimumSize: const Size(0, 52),
              padding: const EdgeInsets.symmetric(horizontal: 24)),
        ),
        OutlinedButton.icon(
          onPressed: onDownload,
          icon: const Icon(Icons.android),
          label: const Text('Get it on Google Play'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 52),
            padding: const EdgeInsets.symmetric(horizontal: 21),
            side: const BorderSide(color: Color(0xFF65543A)),
          ),
        ),
      ]),
      const SizedBox(height: 25),
      const Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.shield_outlined, size: 16, color: _muted),
        SizedBox(width: 8),
        Flexible(
          child: Text('Practice first. Trade with context.',
              style: TextStyle(color: _muted, fontSize: 12)),
        ),
      ]),
      const SizedBox(height: 35),
      const Wrap(spacing: 22, runSpacing: 12, children: [
        _HeroPoint(Icons.candlestick_chart_outlined, 'Interactive charts'),
        _HeroPoint(Icons.bolt_outlined, 'Live market view'),
        _HeroPoint(Icons.explore_outlined, 'Virtual practice'),
      ]),
    ]);

    return Container(
      constraints: BoxConstraints(minHeight: compact ? 690 : 660),
      padding: EdgeInsets.fromLTRB(
          inset, compact ? 55 : 82, inset, compact ? 58 : 82),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF201D1A), Color(0xFF1C1C1C)],
        ),
      ),
      child: stacked
          ? Column(children: [
              copy,
              const SizedBox(height: 38),
              SizedBox(height: compact ? 340 : 440, child: const _HeroVisual()),
            ])
          : Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Expanded(flex: 10, child: copy),
              const SizedBox(width: 36),
              const Expanded(
                  flex: 11, child: SizedBox(height: 530, child: _HeroVisual())),
            ]),
    );
  }
}

class _HeroVisual extends StatefulWidget {
  const _HeroVisual();

  @override
  State<_HeroVisual> createState() => _HeroVisualState();
}

class _HeroVisualState extends State<_HeroVisual>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion;

  @override
  void initState() {
    super.initState();
    _motion =
        AnimationController(vsync: this, duration: const Duration(seconds: 7))
          ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF171512),
          border: Border.all(color: const Color(0xFF56442A)),
          borderRadius: BorderRadius.circular(26),
        ),
        child: Stack(fit: StackFit.expand, children: [
          AnimatedBuilder(
            animation: _motion,
            builder: (context, child) => Transform.scale(
              scale: reduceMotion ? 1 : 1.02 + .025 * _motion.value,
              child: child,
            ),
            child: Image.asset('assets/landing/campaign_coin_v1.png',
                fit: BoxFit.cover),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Color(0xB60C0B0A)],
                stops: [0.45, 1],
              ),
            ),
          ),
          Positioned(
            left: 22,
            right: 22,
            bottom: 22,
            child: AnimatedBuilder(
              animation: _motion,
              builder: (context, child) => Transform.translate(
                offset: Offset(0,
                    reduceMotion ? 0 : -4 * math.sin(_motion.value * math.pi)),
                child: child,
              ),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xE523211D),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0x997B6134)),
                ),
                child: const Row(children: [
                  Icon(Icons.candlestick_chart_outlined,
                      color: _gold, size: 31),
                  SizedBox(width: 13),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Explore the trading workspace',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w800)),
                          SizedBox(height: 4),
                          Text(
                              'Charts, markets and virtual practice in one place',
                              style: TextStyle(color: _muted, fontSize: 11)),
                        ]),
                  ),
                  Icon(Icons.arrow_outward, color: _gold),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _HeroPoint extends StatelessWidget {
  const _HeroPoint(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 17, color: _gold),
        const SizedBox(width: 7),
        Text(label,
            style: const TextStyle(color: Color(0xFFD7CDBB), fontSize: 12)),
      ]);
}

class _LivePreview extends ConsumerStatefulWidget {
  const _LivePreview(
      {required this.compact, required this.inset, required this.onTrade});
  final bool compact;
  final double inset;
  final VoidCallback onTrade;

  @override
  ConsumerState<_LivePreview> createState() => _LivePreviewState();
}

class _LivePreviewState extends ConsumerState<_LivePreview> {
  String assetId = 'btc-usd';
  String interval = '15m';

  @override
  Widget build(BuildContext context) {
    final request = (assetId: assetId, interval: interval, limit: 90);
    final series = ref.watch(liveCandlesProvider(request));
    final narrow = MediaQuery.sizeOf(context).width < 1050;
    final copy =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _Eyebrow('THE PRODUCT, NOT A PROMISE'),
      const SizedBox(height: 17),
      Text('Get closer to the market.',
          style: TextStyle(
              fontSize: widget.compact ? 34 : 49,
              height: 1.06,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.4)),
      const SizedBox(height: 18),
      const Text(
          'Explore actual market candles and moving averages. Change the view here, then step into the full trading workspace to practice your next move.',
          style: TextStyle(color: _muted, fontSize: 16, height: 1.55)),
      const SizedBox(height: 27),
      FilledButton.icon(
          onPressed: widget.onTrade,
          icon: const Icon(Icons.arrow_outward),
          label: const Text('Explore the demo'),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 50))),
      const SizedBox(height: 17),
      const Text('Chart data is for display and may vary by instrument.',
          style: TextStyle(color: _muted, fontSize: 11)),
    ]);
    final chart = Container(
      height: widget.compact ? 390 : 465,
      decoration: BoxDecoration(
          color: const Color(0xFF202225),
          borderRadius: BorderRadius.circular(23),
          border: Border.all(color: const Color(0xFF59472C)),
          boxShadow: const [
            BoxShadow(
                color: Color(0x44000000), blurRadius: 45, offset: Offset(0, 25))
          ]),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
            child: Row(children: [
              const Icon(Icons.circle, color: Color(0xFF45C999), size: 9),
              const SizedBox(width: 8),
              const Text('MARKET VIEW',
                  style: TextStyle(
                      color: _muted,
                      letterSpacing: 1.5,
                      fontSize: 10,
                      fontWeight: FontWeight.w800)),
              const Spacer(),
              const Icon(Icons.candlestick_chart, color: _gold, size: 19),
            ])),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(children: [
              _PreviewChoice('BTC/USD', assetId == 'btc-usd',
                  () => setState(() => assetId = 'btc-usd')),
              const SizedBox(width: 6),
              _PreviewChoice('ETH/USD', assetId == 'eth-usd',
                  () => setState(() => assetId = 'eth-usd')),
              const Spacer(),
              _PreviewChoice('15m', interval == '15m',
                  () => setState(() => interval = '15m')),
              const SizedBox(width: 4),
              _PreviewChoice('1h', interval == '1h',
                  () => setState(() => interval = '1h')),
            ])),
        const Divider(color: Color(0xFF34383C), height: 20),
        Expanded(
            child: series.when(
          data: (data) => LiveTradeChart(series: data, precision: 2),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.wifi_off_outlined, color: _muted, size: 30),
            const SizedBox(height: 10),
            const Text('Market view is temporarily unavailable.',
                style: TextStyle(color: _muted)),
            TextButton(
                onPressed: () => ref.invalidate(liveCandlesProvider(request)),
                child: const Text('Retry')),
          ])),
        )),
      ]),
    );
    return Container(
      padding: EdgeInsets.fromLTRB(widget.inset, widget.compact ? 80 : 120,
          widget.inset, widget.compact ? 80 : 120),
      child: narrow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [copy, const SizedBox(height: 40), chart])
          : Row(children: [
              Expanded(flex: 4, child: copy),
              const SizedBox(width: 65),
              Expanded(flex: 6, child: chart)
            ]),
    );
  }
}

class _PreviewChoice extends StatelessWidget {
  const _PreviewChoice(this.label, this.selected, this.onTap);
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            child: Text(label,
                style: TextStyle(
                    color: selected ? _gold : _muted,
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w500))),
      );
}

class _MarketsShowcase extends StatelessWidget {
  const _MarketsShowcase(
      {required this.compact, required this.inset, required this.onTrade});
  final bool compact;
  final double inset;
  final VoidCallback onTrade;

  @override
  Widget build(BuildContext context) => Container(
        color: const Color(0xFF24211D),
        padding: EdgeInsets.fromLTRB(
            inset, compact ? 80 : 112, inset, compact ? 80 : 115),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _Eyebrow('A WORLD OF MARKETS'),
          const SizedBox(height: 17),
          Text('Follow what moves you.',
              style: TextStyle(
                  fontSize: compact ? 35 : 48,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.2)),
          const SizedBox(height: 12),
          const Text('Discover different markets from one focused workspace.',
              style: TextStyle(color: _muted, fontSize: 16)),
          const SizedBox(height: 32),
          if (compact) ...[
            _MarketImageCard(
                image: 'assets/landing/campaign_coin_v1.png',
                title: 'Digital assets',
                detail:
                    'Explore crypto price action, from major coins to more markets.',
                icon: Icons.currency_bitcoin,
                onTap: onTrade),
            const SizedBox(height: 15),
            _MarketImageCard(
                image: 'assets/landing/global_markets_v1.png',
                title: 'Global markets',
                detail: 'Move between forex, stocks, indices and commodities.',
                icon: Icons.public,
                onTap: onTrade),
          ] else
            Row(children: [
              Expanded(
                  child: _MarketImageCard(
                      image: 'assets/landing/campaign_coin_v1.png',
                      title: 'Digital assets',
                      detail:
                          'Explore crypto price action, from major coins to more markets.',
                      icon: Icons.currency_bitcoin,
                      onTap: onTrade)),
              const SizedBox(width: 20),
              Expanded(
                  child: _MarketImageCard(
                      image: 'assets/landing/global_markets_v1.png',
                      title: 'Global markets',
                      detail:
                          'Move between forex, stocks, indices and commodities.',
                      icon: Icons.public,
                      onTap: onTrade)),
            ]),
        ]),
      );
}

class _MarketImageCard extends StatefulWidget {
  const _MarketImageCard(
      {required this.image,
      required this.title,
      required this.detail,
      required this.icon,
      required this.onTap});
  final String image;
  final String title;
  final String detail;
  final IconData icon;
  final VoidCallback onTap;
  @override
  State<_MarketImageCard> createState() => _MarketImageCardState();
}

class _MarketImageCardState extends State<_MarketImageCard> {
  bool hovered = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => setState(() => hovered = true),
        onExit: (_) => setState(() => hovered = false),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(24),
          child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: SizedBox(
                  height: 370,
                  child: Stack(fit: StackFit.expand, children: [
                    AnimatedScale(
                        scale:
                            hovered && !MediaQuery.disableAnimationsOf(context)
                                ? 1.045
                                : 1,
                        duration: const Duration(milliseconds: 500),
                        curve: Curves.easeOutCubic,
                        child: Image.asset(widget.image, fit: BoxFit.cover)),
                    const DecoratedBox(
                        decoration: BoxDecoration(
                            gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Color(0x12000000), Color(0xDD080808)],
                                stops: [0.3, 1]))),
                    Positioned(
                        left: 26,
                        right: 26,
                        bottom: 26,
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(widget.icon, color: _gold, size: 30),
                              const SizedBox(height: 12),
                              Text(widget.title,
                                  style: const TextStyle(
                                      fontSize: 27,
                                      fontWeight: FontWeight.w900)),
                              const SizedBox(height: 7),
                              Text(widget.detail,
                                  style: const TextStyle(
                                      color: Color(0xFFDFD7C9), height: 1.4)),
                              const SizedBox(height: 14),
                              const Row(children: [
                                Text('Explore markets',
                                    style: TextStyle(
                                        color: _gold,
                                        fontWeight: FontWeight.w700)),
                                SizedBox(width: 7),
                                Icon(Icons.arrow_forward,
                                    color: _gold, size: 17)
                              ]),
                            ])),
                  ]))),
        ),
      );
}

class _MarketBand extends StatefulWidget {
  const _MarketBand({required this.compact, required this.inset});
  final bool compact;
  final double inset;

  @override
  State<_MarketBand> createState() => _MarketBandState();
}

class _MarketBandState extends State<_MarketBand>
    with SingleTickerProviderStateMixin {
  late final AnimationController motion;

  @override
  void initState() {
    super.initState();
    motion =
        AnimationController(vsync: this, duration: const Duration(seconds: 22))
          ..repeat();
  }

  @override
  void dispose() {
    motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
        height: 66,
        decoration: const BoxDecoration(
          color: Color(0xFF26221D),
          border: Border.symmetric(
              horizontal: BorderSide(color: Color(0xFF3D352B))),
        ),
        child: ClipRect(child: LayoutBuilder(builder: (context, constraints) {
          final groupWidth = widget.compact ? 830.0 : 1260.0;
          final reduceMotion = MediaQuery.disableAnimationsOf(context);
          return AnimatedBuilder(
              animation: motion,
              builder: (context, _) => Transform.translate(
                    offset: Offset(
                        reduceMotion ? 0 : -groupWidth * motion.value, 0),
                    child: OverflowBox(
                      alignment: Alignment.centerLeft,
                      minWidth: groupWidth * 2,
                      maxWidth: groupWidth * 2,
                      child: Row(children: [
                        for (var i = 0; i < 2; i++)
                          SizedBox(
                              width: groupWidth,
                              child: const Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceAround,
                                  children: [
                                    _BandItem(Icons.currency_bitcoin, 'CRYPTO'),
                                    _BandItem(Icons.currency_exchange, 'FOREX'),
                                    _BandItem(
                                        Icons.show_chart, 'STOCKS & INDICES'),
                                    _BandItem(
                                        Icons.diamond_outlined, 'COMMODITIES'),
                                  ]))
                      ]),
                    ),
                  ));
        })),
      );
}

class _BandItem extends StatelessWidget {
  const _BandItem(this.icon, this.label);
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: _gold, size: 20),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      ]);
}

class _FeatureSection extends StatelessWidget {
  const _FeatureSection({required this.compact, required this.inset});
  final bool compact;
  final double inset;

  @override
  Widget build(BuildContext context) {
    const cards = [
      _FeatureCard(Icons.candlestick_chart_outlined, 'See the market clearly',
          'Explore interactive candle charts, moving averages and market performance across available assets.'),
      _FeatureCard(Icons.school_outlined, 'Practice before you commit',
          'Use a virtual demo balance to learn the flow, place trades and review the outcome.'),
      _FeatureCard(Icons.devices_outlined, 'Move between web and app',
          'Trade in your browser or download Zettax for Android, using the same Zettax account.'),
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(
          inset, compact ? 66 : 110, inset, compact ? 70 : 112),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _Eyebrow('BUILT FOR A BETTER VIEW'),
        const SizedBox(height: 15),
        Text('Everything you need to explore.',
            style: TextStyle(
                fontSize: compact ? 32 : 44,
                height: 1.1,
                letterSpacing: -1.2,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 13),
        const Text('A focused experience for learning, watching and trading.',
            style: TextStyle(color: _muted, fontSize: 16)),
        const SizedBox(height: 34),
        if (compact)
          Column(children: [
            for (final card in cards) ...[
              card,
              SizedBox(height: 14),
            ],
          ])
        else
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final card in cards) ...[
              Expanded(child: card),
              SizedBox(width: 18),
            ],
          ]),
      ]),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard(this.icon, this.title, this.body);
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => _Entrance(
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 225),
          padding: const EdgeInsets.all(27),
          decoration: BoxDecoration(
            color: PrimeVestDesignSystem.surfaceDark,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFF40382F)),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0x33F8B425),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: _gold, size: 27),
            ),
            const SizedBox(height: 23),
            Text(title,
                style:
                    const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Text(body,
                style:
                    const TextStyle(color: _muted, height: 1.5, fontSize: 14)),
          ]),
        ),
      );
}

class _StepsSection extends StatelessWidget {
  const _StepsSection({required this.compact, required this.inset});
  final bool compact;
  final double inset;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.fromLTRB(
            inset, compact ? 70 : 100, inset, compact ? 72 : 100),
        color: const Color(0xFF24211D),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _Eyebrow('HOW IT WORKS'),
          const SizedBox(height: 16),
          Text('Start with practice. Build your perspective.',
              style: TextStyle(
                  fontSize: compact ? 31 : 42,
                  height: 1.15,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 32),
          if (compact)
            const Column(children: [
              _Step('01', 'Open the workspace',
                  'Jump straight into the demo trading screen.'),
              SizedBox(height: 12),
              _Step('02', 'Explore the chart',
                  'Choose a market, view price history and set a practice amount.'),
              SizedBox(height: 12),
              _Step('03', 'Review your activity',
                  'Track your virtual balance, open trades and history.'),
            ])
          else
            const Row(children: [
              Expanded(
                  child: _Step('01', 'Open the workspace',
                      'Jump straight into the demo trading screen.')),
              SizedBox(width: 22),
              Expanded(
                  child: _Step('02', 'Explore the chart',
                      'Choose a market, view price history and set a practice amount.')),
              SizedBox(width: 22),
              Expanded(
                  child: _Step('03', 'Review your activity',
                      'Track your virtual balance, open trades and history.')),
            ]),
        ]),
      );
}

class _FaqSection extends StatelessWidget {
  const _FaqSection({required this.compact, required this.inset});
  final bool compact;
  final double inset;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(
            inset, compact ? 78 : 112, inset, compact ? 74 : 108),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _Eyebrow('THE DETAILS THAT MATTER'),
          const SizedBox(height: 16),
          Text('Explore with confidence.',
              style: TextStyle(
                  fontSize: compact ? 34 : 46,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.1)),
          const SizedBox(height: 26),
          const _FaqTile('Can I explore before creating an account?',
              'Yes. Open the demo trading workspace to explore markets and practice with virtual funds.'),
          const _FaqTile('Is the demo balance real money?',
              'No. Demo funds are virtual and cannot be withdrawn. They are there to help you learn the experience.'),
          const _FaqTile('Can I use Zettax on my phone?',
              'Yes. The website adapts to mobile screens, and the Android app is available to download here.'),
          const _FaqTile('Where can I learn about trading risks?',
              'Read the Risk disclosure and Help & education pages before making decisions.'),
        ]),
      );
}

class _FaqTile extends StatelessWidget {
  const _FaqTile(this.question, this.answer);
  final String question;
  final String answer;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
            color: PrimeVestDesignSystem.surfaceDark,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: Color(0xFF40382F))),
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
                title: Text(question,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 16)),
                iconColor: _gold,
                collapsedIconColor: _gold,
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 19),
                expandedAlignment: Alignment.centerLeft,
                children: [
                  Text(answer,
                      style: const TextStyle(color: _muted, height: 1.55))
                ])),
      );
}

class _Step extends StatelessWidget {
  const _Step(this.number, this.title, this.body);
  final String number;
  final String title;
  final String body;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(23),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFF574930)),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(number,
              style: const TextStyle(
                  color: _gold, fontSize: 25, fontWeight: FontWeight.w900)),
          const SizedBox(height: 15),
          Text(title,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(body, style: const TextStyle(color: _muted, height: 1.5)),
        ]),
      );
}

class _DownloadSection extends StatelessWidget {
  const _DownloadSection({
    required this.compact,
    required this.inset,
    required this.onTrade,
    required this.onDownload,
  });
  final bool compact;
  final double inset;
  final VoidCallback onTrade;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(
            inset, compact ? 70 : 100, inset, compact ? 70 : 100),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.all(compact ? 28 : 52),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [
              Color(0xFF3C2E17),
              Color(0xFF27211A),
              Color(0xFF201D1A),
            ]),
            border: Border.all(color: const Color(0xFF7B6031)),
            borderRadius: BorderRadius.circular(26),
          ),
          child: compact
              ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const _DownloadArt(height: 195),
                  const SizedBox(height: 25),
                  _downloadCopy,
                  const SizedBox(height: 24),
                  _downloadButtons(),
                ])
              : Row(children: [
                  Expanded(
                      flex: 5,
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _downloadCopy,
                            const SizedBox(height: 24),
                            SizedBox(width: 270, child: _downloadButtons()),
                          ])),
                  const SizedBox(width: 36),
                  const Expanded(flex: 4, child: _DownloadArt(height: 265)),
                ]),
        ),
      );

  Widget get _downloadCopy => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Eyebrow('TAKE ZETTAX WITH YOU'),
          SizedBox(height: 13),
          Text('Your workspace, wherever you are.',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
          SizedBox(height: 9),
          Text(
              'Get the Android app on Google Play or keep trading in your browser.',
              style: TextStyle(color: _muted, height: 1.5)),
        ],
      );

  Widget _downloadButtons() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: onDownload,
            icon: const Icon(Icons.download_outlined),
            label: const Text('Get it on Google Play'),
            style: FilledButton.styleFrom(minimumSize: const Size(230, 52)),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: onTrade,
            child: const Text('Continue on web →'),
          ),
        ],
      );
}

class _DownloadArt extends StatelessWidget {
  const _DownloadArt({required this.height});
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        width: double.infinity,
        child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(fit: StackFit.expand, children: [
              Image.asset('assets/landing/market_energy.png',
                  fit: BoxFit.cover),
              const DecoratedBox(
                  decoration: BoxDecoration(
                      gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0xB0000000)]))),
              const Positioned(
                  left: 20,
                  bottom: 20,
                  child: Row(children: [
                    Icon(Icons.android, color: _gold, size: 24),
                    SizedBox(width: 9),
                    Text('ZETTAX FOR ANDROID',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2)),
                  ])),
            ])),
      );
}

class _LandingFooter extends StatelessWidget {
  const _LandingFooter({
    required this.compact,
    required this.inset,
    required this.onTrade,
    required this.onDownload,
  });
  final bool compact;
  final double inset;
  final VoidCallback onTrade;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.fromLTRB(inset, 45, inset, 30),
        color: const Color(0xFF171615),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (compact)
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _brand(),
              const SizedBox(height: 26),
              _links(context),
            ])
          else
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: _brand()),
              _links(context),
            ]),
          const SizedBox(height: 35),
          const Divider(color: Color(0xFF3D352B)),
          const SizedBox(height: 16),
          const Text(
            'Trading involves risk. Demo activity uses virtual funds and does not guarantee future results. Market data may be delayed or sampled depending on the instrument.',
            style: TextStyle(color: _muted, height: 1.5, fontSize: 12),
          ),
          const SizedBox(height: 15),
          const Text('© Zettax', style: TextStyle(color: _muted, fontSize: 12)),
        ]),
      );

  Widget _brand() => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            ZettaxMark(height: 37),
            SizedBox(width: 10),
            Text('Zettax',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          ]),
          SizedBox(height: 12),
          Text('Explore. Practice. Trade.', style: TextStyle(color: _muted)),
        ],
      );

  Widget _links(BuildContext context) =>
      Wrap(spacing: 10, runSpacing: 5, children: [
        TextButton(onPressed: onTrade, child: const Text('Demo trading')),
        TextButton(
            onPressed: () => context.push('/login'),
            child: const Text('Sign in')),
        TextButton(
            onPressed: () => context.push('/education'),
            child: const Text('Help & education')),
        TextButton(
            onPressed: () => context.push('/risk'),
            child: const Text('Risk disclosure')),
        TextButton(onPressed: onDownload, child: const Text('Google Play')),
      ]);
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          color: _gold,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 2));
}

class _Entrance extends StatelessWidget {
  const _Entrance({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
            offset: Offset(0, (1 - value) * 18), child: child),
      ),
      child: child,
    );
  }
}
