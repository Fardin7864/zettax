import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:primevest_mobile/app/brand_logo.dart';
import 'package:primevest_mobile/app/design_system.dart';
import 'package:url_launcher/url_launcher.dart';

const _gold = PrimeVestDesignSystem.primaryGold;
const _muted = PrimeVestDesignSystem.textMuted;
const _downloadUrl = 'https://zettax.app/downloads/zettax-latest.apk';

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
              _FeatureSection(compact: compact, inset: inset),
              _StepsSection(compact: compact, inset: inset),
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
    final copy =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _Entrance(
        child: _Eyebrow('YOUR MARKET WORKSPACE'),
      ),
      const SizedBox(height: 22),
      _Entrance(
        child: Text.rich(
          TextSpan(children: [
            const TextSpan(text: 'A clearer way to\n'),
            TextSpan(
                text: 'explore trading.', style: const TextStyle(color: _gold)),
          ]),
          style: TextStyle(
            fontSize: compact ? 43 : 67,
            height: 1.05,
            letterSpacing: -2.2,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      const SizedBox(height: 24),
      const _Entrance(
        child: Text(
          'Explore markets, study price movement, and practice with virtual funds. Your trading workspace is ready on web and Android.',
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
          label: const Text('Download Android app'),
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
    ]);

    return Container(
      padding: EdgeInsets.fromLTRB(
          inset, compact ? 58 : 92, inset, compact ? 58 : 94),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF201D1A), Color(0xFF1C1C1C)],
        ),
      ),
      child: compact
          ? Column(children: [
              copy,
              const SizedBox(height: 38),
              const SizedBox(height: 320, child: _HeroVisual()),
            ])
          : Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Expanded(flex: 10, child: copy),
              const SizedBox(width: 36),
              const Expanded(
                  flex: 11, child: SizedBox(height: 500, child: _HeroVisual())),
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
            child: Image.asset('assets/landing/market_energy.png',
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

class _MarketBand extends StatelessWidget {
  const _MarketBand({required this.compact, required this.inset});
  final bool compact;
  final double inset;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: inset, vertical: 22),
        decoration: const BoxDecoration(
          color: Color(0xFF26221D),
          border: Border.symmetric(
              horizontal: BorderSide(color: Color(0xFF3D352B))),
        ),
        child: compact
            ? const Column(children: [
                _BandItem(Icons.currency_bitcoin, 'Crypto'),
                SizedBox(height: 15),
                _BandItem(Icons.currency_exchange, 'Forex'),
                SizedBox(height: 15),
                _BandItem(Icons.show_chart, 'Stocks & indices'),
              ])
            : const Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                    _BandItem(Icons.currency_bitcoin, 'Crypto'),
                    _BandItem(Icons.currency_exchange, 'Forex'),
                    _BandItem(Icons.show_chart, 'Stocks & indices'),
                    _BandItem(Icons.diamond_outlined, 'Commodities'),
                  ]),
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
                  const Icon(Icons.android, color: _gold, size: 48),
                  const SizedBox(height: 18),
                  _downloadCopy,
                  const SizedBox(height: 24),
                  _downloadButtons(),
                ])
              : Row(children: [
                  const Icon(Icons.android, color: _gold, size: 58),
                  const SizedBox(width: 28),
                  Expanded(child: _downloadCopy),
                  const SizedBox(width: 28),
                  SizedBox(width: 250, child: _downloadButtons()),
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
          Text('Download the Android app or keep trading in your browser.',
              style: TextStyle(color: _muted, height: 1.5)),
        ],
      );

  Widget _downloadButtons() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: onDownload,
            icon: const Icon(Icons.download_outlined),
            label: const Text('Download for Android'),
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
        TextButton(onPressed: onDownload, child: const Text('Android app')),
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
