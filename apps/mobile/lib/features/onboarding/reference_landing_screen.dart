import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:primevest_mobile/app/brand_logo.dart';
import 'package:primevest_mobile/features/onboarding/download_analytics_stub.dart'
    if (dart.library.js_interop) 'package:primevest_mobile/features/onboarding/download_analytics_web.dart';
import 'package:url_launcher/url_launcher.dart';

const _navy = Color(0xFF071620);
const _panel = Color(0xFF11232D);
const _panelLight = Color(0xFF182B36);
const _edge = Color(0xFF2B414C);
const _gold = Color(0xFFFFCB69);
const _muted = Color(0xFFACBAC3);
const _green = Color(0xFF1DCE9C);
const _asset = 'assets/landing/reference/';
const _playUrl =
    'https://play.google.com/store/apps/details?id=com.primevest.app';

class WebLandingScreen extends StatefulWidget {
  const WebLandingScreen({super.key});

  @override
  State<WebLandingScreen> createState() => _WebLandingScreenState();
}

class _WebLandingScreenState extends State<WebLandingScreen> {
  final _markets = GlobalKey();
  final _features = GlobalKey();
  final _steps = GlobalKey();
  final _demo = GlobalKey();
  final _learn = GlobalKey();
  final _faq = GlobalKey();

  void _goTo(GlobalKey key) {
    final target = key.currentContext;
    if (target != null) {
      Scrollable.ensureVisible(target,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
          alignment: 0.01);
    }
  }

  void _trade() => context.go('/home?tab=2');

  Future<void> _download(String source) async {
    trackDownloadClick(source);
    await launchUrl(Uri.parse(_playUrl), webOnlyWindowName: '_blank');
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final mobile = width < 760;
    final navCompact = width < 1340;
    final pad = mobile
        ? 18.0
        : width < 1100
            ? 30.0
            : 42.0;
    return Scaffold(
      backgroundColor: _navy,
      body: SafeArea(
        child: Column(children: [
          LandingNavbar(
            compact: navCompact,
            onMarkets: () => _goTo(_markets),
            onFeatures: () => _goTo(_features),
            onHowItWorks: () => _goTo(_steps),
            onDemo: () => _goTo(_demo),
            onLearn: () => _goTo(_learn),
            onFaq: () => _goTo(_faq),
            onLogin: () => context.push('/login'),
            onTryDemo: _trade,
            onDownload: () => _download('navbar'),
          ),
          Expanded(
              child: SingleChildScrollView(
            child: Center(
                child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1900),
              child: Column(children: [
                _Hero(
                    mobile: mobile,
                    pad: pad,
                    onDemo: _trade,
                    onDownload: () => _download('hero')),
                KeyedSubtree(
                    key: _markets,
                    child: _Markets(mobile: mobile, pad: pad, onTrade: _trade)),
                _WhyChoose(mobile: mobile, pad: pad),
                KeyedSubtree(
                    key: _features, child: _Features(mobile: mobile, pad: pad)),
                KeyedSubtree(
                    key: _demo,
                    child: _Charting(mobile: mobile, pad: pad, onDemo: _trade)),
                KeyedSubtree(
                    key: _steps, child: _Steps(mobile: mobile, pad: pad)),
                _LearningGuide(
                    mobile: mobile,
                    pad: pad,
                    onLearn: () => context.push('/education')),
                _AppGallery(mobile: mobile, pad: pad),
                _Trust(mobile: mobile, pad: pad),
                KeyedSubtree(
                    key: _learn,
                    child: _Academy(
                        mobile: mobile,
                        pad: pad,
                        onLearn: () => context.push('/education'))),
                _Community(mobile: mobile, pad: pad),
                KeyedSubtree(key: _faq, child: _Faq(mobile: mobile, pad: pad)),
                _Footer(
                    mobile: mobile,
                    pad: pad,
                    onDemo: _trade,
                    onDownload: () => _download('footer'),
                    onLearn: () => context.push('/education'),
                    onLogin: () => context.push('/login')),
              ]),
            )),
          )),
        ]),
      ),
    );
  }
}

class LandingNavbar extends StatelessWidget {
  const LandingNavbar(
      {super.key,
      required this.compact,
      required this.onMarkets,
      required this.onFeatures,
      required this.onHowItWorks,
      required this.onDemo,
      required this.onLearn,
      required this.onFaq,
      required this.onLogin,
      required this.onTryDemo,
      required this.onDownload});
  final bool compact;
  final VoidCallback onMarkets,
      onFeatures,
      onHowItWorks,
      onDemo,
      onLearn,
      onFaq,
      onLogin,
      onTryDemo,
      onDownload;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final tiny = width < 360;
    final scale = MediaQuery.textScalerOf(context).scale(17);
    final showName = !tiny || scale <= 20;
    final menu = <(String, VoidCallback)>[
      ('Markets', onMarkets),
      ('Features', onFeatures),
      ('How It Works', onHowItWorks),
      ('Demo Trading', onDemo),
      ('Learn', onLearn),
      ('FAQ', onFaq),
      ('Login', onLogin),
      ('Try Demo Trading', onTryDemo),
    ];
    return Container(
      height: compact ? 62 : 72,
      padding:
          EdgeInsets.symmetric(horizontal: compact ? (tiny ? 10 : 16) : 38),
      decoration: const BoxDecoration(
          color: Color(0xF207151F),
          border: Border(bottom: BorderSide(color: _edge))),
      child: Row(children: [
        ZettaxMark(height: compact ? 29 : 33),
        if (showName) ...[
          const SizedBox(width: 5),
          Text('Zettax',
              style: TextStyle(
                  fontSize: compact ? (tiny ? 17 : 19) : 22,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
        ],
        const Spacer(),
        if (!compact) ...[
          _link('Markets', onMarkets),
          _link('Features', onFeatures),
          _link('How It Works', onHowItWorks),
          _link('Demo', onDemo),
          _link('Learn', onLearn),
          _link('FAQ', onFaq),
          const Spacer(),
          _link('Login', onLogin),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: onTryDemo, child: const Text('Try Demo')),
          const SizedBox(width: 10),
        ],
        FilledButton(
          key: const Key('navbar-download'),
          onPressed: onDownload,
          style: FilledButton.styleFrom(
            backgroundColor: _gold,
            foregroundColor: _navy,
            minimumSize: Size(0, compact ? 44 : 46),
            padding: EdgeInsets.symmetric(
                horizontal: compact ? (tiny ? 9 : 13) : 18),
            textStyle:
                const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
          child: Text(compact ? 'Download' : 'Download App', maxLines: 1),
        ),
        if (compact) ...[
          SizedBox(width: tiny ? 5 : 8),
          PopupMenuButton<int>(
            key: const Key('navbar-menu'),
            tooltip: 'Open menu',
            icon: const Icon(Icons.menu_rounded),
            onSelected: (i) => menu[i].$2(),
            itemBuilder: (_) => [
              for (var i = 0; i < menu.length; i++)
                PopupMenuItem(value: i, child: Text(menu[i].$1))
            ],
          ),
        ],
      ]),
    );
  }

  Widget _link(String title, VoidCallback action) => TextButton(
        onPressed: action,
        style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            textStyle: const TextStyle(fontSize: 13)),
        child: Text(title, maxLines: 1),
      );
}

class _Hero extends StatelessWidget {
  const _Hero(
      {required this.mobile,
      required this.pad,
      required this.onDemo,
      required this.onDownload});
  final bool mobile;
  final double pad;
  final VoidCallback onDemo, onDownload;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final stacked = width < 1050;
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(minHeight: mobile ? 680 : 570),
      decoration: BoxDecoration(
          image: DecorationImage(
              image: AssetImage(
                  '$_asset${mobile ? 'mountain_hero_portrait' : 'mountain_hero_wide'}.webp'),
              fit: BoxFit.cover,
              alignment: mobile ? Alignment.center : Alignment.centerRight),
          border: const Border(bottom: BorderSide(color: _edge))),
      child: DecoratedBox(
        decoration: const BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
              Color(0xE807151F),
              Color(0xA0081722),
              Color(0x33081722)
            ])),
        child: Padding(
          padding:
              EdgeInsets.fromLTRB(pad, mobile ? 30 : 38, pad, mobile ? 30 : 38),
          child: stacked
              ? Column(
                  crossAxisAlignment: mobile
                      ? CrossAxisAlignment.center
                      : CrossAxisAlignment.start,
                  children: [
                      _heroCopy(context),
                      const SizedBox(height: 18),
                      _HeroPhone(height: mobile ? 330 : 420),
                      if (mobile) ...[
                        const SizedBox(height: 8),
                        _heroActions(context, vertical: true),
                        const SizedBox(height: 12),
                        const _PlatformLabel(),
                      ],
                    ])
              : Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  Expanded(
                      flex: 5,
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _heroCopy(context),
                            const SizedBox(height: 25),
                            _heroActions(context),
                            const SizedBox(height: 19),
                            const _PlatformLabel(),
                          ])),
                  const Expanded(flex: 5, child: _HeroPhone(height: 510)),
                  const SizedBox(width: 8),
                  SizedBox(
                      width: 265,
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _HeroMarketCard(onDemo: onDemo),
                            const SizedBox(height: 12),
                            _DemoCard(onDemo: onDemo),
                          ])),
                ]),
        ),
      ),
    );
  }

  Widget _heroCopy(BuildContext context) => Column(
        crossAxisAlignment:
            mobile ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          const _Eyebrow('TRADE SMARTER  •  A BRIGHTER FINANCIAL FUTURE'),
          const SizedBox(height: 15),
          Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'Trade. Learn.\n'),
                const TextSpan(text: 'Explore '),
                const TextSpan(
                    text: 'Markets.', style: TextStyle(color: _gold)),
              ]),
              textAlign: mobile ? TextAlign.center : TextAlign.left,
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  height: 1.03,
                  letterSpacing: -1.6,
                  fontSize: mobile ? 37 : 58)),
          const SizedBox(height: 16),
          Text(
              'Access global markets—crypto, forex, stocks, commodities and indices—all in one powerful app.',
              textAlign: mobile ? TextAlign.center : TextAlign.left,
              style: const TextStyle(
                  color: Color(0xFFE5EBEE), fontSize: 16, height: 1.5)),
          if (!mobile) const SizedBox(height: 1),
        ],
      );

  Widget _heroActions(BuildContext context, {bool vertical = false}) {
    final buttons = [
      _GoldButton('Download Zettax', Icons.download_rounded, onDownload),
      _OutlineButton('Try Demo Trading', Icons.arrow_forward_rounded, onDemo),
    ];
    return vertical
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [buttons[0], const SizedBox(height: 9), buttons[1]])
        : Wrap(spacing: 10, runSpacing: 10, children: buttons);
  }
}

class _HeroPhone extends StatelessWidget {
  const _HeroPhone({required this.height});
  final double height;

  @override
  Widget build(BuildContext context) => ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => const LinearGradient(
          colors: [
            Colors.transparent,
            Colors.black,
            Colors.black,
            Colors.transparent
          ],
          stops: [0, 0.12, 0.88, 1],
        ).createShader(rect),
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.black,
              Colors.black,
              Colors.transparent
            ],
            stops: [0, 0.08, 0.92, 1],
          ).createShader(rect),
          child: Image.asset('$_asset' 'phone_trade.webp',
              height: height, fit: BoxFit.contain),
        ),
      );
}

class _PlatformLabel extends StatelessWidget {
  const _PlatformLabel();
  @override
  Widget build(BuildContext context) =>
      const Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.android, color: Colors.white, size: 19),
        SizedBox(width: 8),
        Text('Available on Android',
            style: TextStyle(
                color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600))
      ]);
}

class _HeroMarketCard extends StatelessWidget {
  const _HeroMarketCard({required this.onDemo});
  final VoidCallback onDemo;
  @override
  Widget build(BuildContext context) => _GlassCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Expanded(
              child: Text('Explore Markets',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
          Icon(Icons.arrow_outward, size: 17, color: _gold)
        ]),
        const SizedBox(height: 12),
        for (final item in const [
          ('₿', 'Crypto'),
          ('↗', 'Forex'),
          ('◆', 'Commodities'),
          ('▥', 'Stocks')
        ])
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                CircleAvatar(
                    radius: 11,
                    backgroundColor: _panelLight,
                    child: Text(item.$1,
                        style: const TextStyle(color: _gold, fontSize: 11))),
                const SizedBox(width: 8),
                Text(item.$2),
                const Spacer(),
                const Icon(Icons.chevron_right, color: _muted, size: 17),
              ])),
        Align(
            alignment: Alignment.centerRight,
            child: TextButton(
                onPressed: onDemo, child: const Text('View all markets →'))),
      ]));
}

class _DemoCard extends StatelessWidget {
  const _DemoCard({required this.onDemo});
  final VoidCallback onDemo;
  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onDemo,
      child: _GlassCard(
        child: Row(children: [
          const Icon(Icons.account_balance_wallet_outlined,
              color: _gold, size: 28),
          const SizedBox(width: 10),
          const Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('Demo account',
                    style: TextStyle(fontSize: 12, color: _muted)),
                Text('Practice with virtual funds',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              ])),
          const Icon(Icons.arrow_forward_ios, size: 14, color: _gold),
        ]),
      ));
}

class _Markets extends StatelessWidget {
  const _Markets(
      {required this.mobile, required this.pad, required this.onTrade});
  final bool mobile;
  final double pad;
  final VoidCallback onTrade;
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = width < 360
        ? 2
        : mobile
            ? 3
            : 5;
    const markets = [
      ('Crypto', 'Bitcoin, Ethereum and more', 0, 0),
      ('Forex', 'Major and minor pairs', 1, 0),
      ('Stocks', 'Explore global companies', 2, 0),
      ('Commodities', 'Gold, oil and more', 3, 0),
      ('Indices', 'Major global indices', 4, 0),
    ];
    return _Section(
        pad: pad,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _SectionTitle(
              eyebrow: 'EXPLORE',
              title: 'Explore Global Markets',
              subtitle: 'Discover different markets and find what moves you.',
              action: 'View all markets →',
              onAction: onTrade,
              mobile: mobile),
          const SizedBox(height: 22),
          _Grid(columns: columns, gap: 10, children: [
            for (final item in markets)
              _Tile(
                  onTap: onTrade,
                  height: mobile ? 155 : 150,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Sprite(
                            col: item.$3, row: item.$4, size: mobile ? 35 : 44),
                        const Spacer(),
                        Text(item.$1,
                            style: TextStyle(
                                fontSize: mobile ? 13 : 16,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(item.$2,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: mobile ? 10 : 12,
                                color: _muted,
                                height: 1.25)),
                      ])),
          ]),
        ]));
  }
}

class _WhyChoose extends StatelessWidget {
  const _WhyChoose({required this.mobile, required this.pad});
  final bool mobile;
  final double pad;
  @override
  Widget build(BuildContext context) {
    const items = [
      ('Low friction', 'An easy-to-use space to explore markets.', 5, 0),
      ('Global markets', 'Access multiple asset classes in one view.', 0, 1),
      ('Powerful tools', 'Candles, chart overlays and indicators.', 1, 1),
      ('Demo trading', 'Practice with virtual funds first.', 2, 1),
      ('Security controls', 'Account tools to help protect access.', 3, 1),
      ('Learn & grow', 'Educational content for every level.', 4, 1),
    ];
    return _Section(
        pad: pad,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _SectionTitle(
              eyebrow: 'WHY CHOOSE ZETTAX',
              title: 'A Smarter Way to Trade',
              subtitle:
                  'Everything you need to explore, learn and grow—in one powerful app.',
              mobile: mobile),
          const SizedBox(height: 22),
          _Grid(columns: mobile ? 1 : 6, gap: 10, children: [
            for (final item in items)
              _Tile(
                  height: mobile ? 102 : 137,
                  child: mobile
                      ? Row(children: [
                          _Sprite(col: item.$3, row: item.$4, size: 40),
                          const SizedBox(width: 12),
                          Expanded(child: _CardText(item.$1, item.$2))
                        ])
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                              _Sprite(col: item.$3, row: item.$4, size: 34),
                              const Spacer(),
                              _CardText(item.$1, item.$2),
                            ])),
          ]),
        ]));
  }
}

class _Features extends StatelessWidget {
  const _Features({required this.mobile, required this.pad});
  final bool mobile;
  final double pad;
  @override
  Widget build(BuildContext context) {
    const items = [
      ('Real-time charts', 'Follow price movement and indicators.', 5, 1),
      ('Demo trading', 'Practice the flow with virtual funds.', 0, 2),
      ('Multiple markets', 'Crypto, forex, stocks and more.', 1, 2),
      ('Price alerts', 'Get notified about market movements.', 2, 2),
      ('Watchlists', 'Keep your favorite assets close.', 3, 2),
      ('Portfolio tracking', 'Review your positions in one view.', 4, 2),
      ('English & Bangla', 'Use your preferred language.', 5, 2),
      ('Funding requests', 'Review deposit and withdrawal history.', 0, 3),
      ('Secure account', 'Manage your profile and account security.', 1, 3),
      ('Security options', 'Additional account safeguards.', 2, 3),
      ('Market insights', 'Explore data and trading ideas.', 3, 3),
      ('Educational guides', 'Learn about tools and market risk.', 4, 3),
    ];
    return _Section(
        pad: pad,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _SectionTitle(
              eyebrow: 'KEY FEATURES',
              title: 'Everything You Need for Smarter Trading',
              mobile: mobile),
          const SizedBox(height: 22),
          _Grid(columns: mobile ? 2 : 6, gap: 9, children: [
            for (final item in items)
              _Tile(
                  height: mobile ? 126 : 132,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Sprite(col: item.$3, row: item.$4, size: 33),
                        const Spacer(),
                        _CardText(item.$1, item.$2),
                      ])),
          ]),
        ]));
  }
}

class _Charting extends StatelessWidget {
  const _Charting(
      {required this.mobile, required this.pad, required this.onDemo});
  final bool mobile;
  final double pad;
  final VoidCallback onDemo;
  @override
  Widget build(BuildContext context) {
    const tools = [
      'Interactive candlestick charts',
      'Technical indicators',
      'Multiple timeframes',
      'Drawing and chart tools',
      'Market performance',
    ];
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
          image: DecorationImage(
              image: AssetImage('$_asset' 'mountain_band.webp'),
              fit: BoxFit.cover),
          border: Border.symmetric(horizontal: BorderSide(color: _edge))),
      child: Container(
        color: const Color(0xA307151F),
        padding:
            EdgeInsets.fromLTRB(pad, mobile ? 38 : 56, pad, mobile ? 38 : 56),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _SectionTitle(
              eyebrow: 'PROFESSIONAL CHARTING',
              title: 'Advanced Charts & Trading Tools',
              subtitle:
                  'Analyze markets with powerful charts, technical indicators and market data.',
              mobile: mobile),
          const SizedBox(height: 24),
          if (mobile) ...[
            for (final tool in tools)
              Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _CheckLine(tool)),
            const SizedBox(height: 14),
            Center(child: _ChartImage(onDemo: onDemo, mobile: mobile)),
          ] else
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              SizedBox(
                  width: 235,
                  child: Column(children: [
                    for (final tool in tools)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 15),
                          child: _CheckLine(tool)),
                  ])),
              const SizedBox(width: 22),
              Expanded(child: _ChartImage(onDemo: onDemo, mobile: mobile)),
            ]),
          const SizedBox(height: 10),
          const Text(
              'Illustrative workspace preview. Display data may vary by instrument.',
              style: TextStyle(fontSize: 11, color: _muted)),
        ]),
      ),
    );
  }
}

class _ChartImage extends StatelessWidget {
  const _ChartImage({required this.onDemo, required this.mobile});
  final VoidCallback onDemo;
  final bool mobile;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onDemo,
        child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: Image.asset(
                '$_asset${mobile ? 'phone_trade_alt' : 'chart_desktop'}.webp',
                height: mobile ? 390 : null,
                fit: BoxFit.contain)),
      );
}

class _CheckLine extends StatelessWidget {
  const _CheckLine(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Row(children: [
        const Icon(Icons.check_circle_outline, color: _green, size: 22),
        const SizedBox(width: 10),
        Flexible(child: Text(text, style: const TextStyle(fontSize: 13))),
      ]);
}

class _Steps extends StatelessWidget {
  const _Steps({required this.mobile, required this.pad});
  final bool mobile;
  final double pad;
  @override
  Widget build(BuildContext context) {
    const steps = [
      ('Create an account', 'Sign up with email or Google.'),
      ('Try demo trading', 'Practice with virtual funds.'),
      ('Explore charts', 'Study candles and indicators.'),
      ('Build a watchlist', 'Follow markets that interest you.'),
      ('Review activity', 'Track your positions and outcomes.'),
    ];
    return _Section(
        pad: pad,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _SectionTitle(
              eyebrow: 'GET STARTED',
              title: 'How It Works',
              subtitle: 'Get started with Zettax in five simple steps.',
              mobile: mobile),
          const SizedBox(height: 22),
          _Grid(columns: mobile ? 1 : 5, gap: mobile ? 9 : 13, children: [
            for (var i = 0; i < steps.length; i++)
              mobile
                  ? _Tile(
                      height: 104,
                      child: Row(children: [
                        _StepNumber(i + 1),
                        const SizedBox(width: 12),
                        Expanded(child: _CardText(steps[i].$1, steps[i].$2)),
                      ]))
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                          _StepNumber(i + 1),
                          const SizedBox(width: 9),
                          Expanded(child: _CardText(steps[i].$1, steps[i].$2)),
                        ]),
          ]),
        ]));
  }
}

class _StepNumber extends StatelessWidget {
  const _StepNumber(this.number);
  final int number;
  @override
  Widget build(BuildContext context) => Container(
      width: 29,
      height: 29,
      alignment: Alignment.center,
      decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(colors: [_green, Color(0xFF136D71)]),
          border: Border.all(color: Colors.white54)),
      child: Text('$number',
          style: const TextStyle(
              fontWeight: FontWeight.w800, fontSize: 12, color: Colors.white)));
}

class _LearningGuide extends StatelessWidget {
  const _LearningGuide(
      {required this.mobile, required this.pad, required this.onLearn});
  final bool mobile;
  final double pad;
  final VoidCallback onLearn;
  @override
  Widget build(BuildContext context) => _Section(
      pad: pad,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _SectionTitle(
            eyebrow: 'LEARN BY DOING',
            title: 'How to Trade on Zettax',
            subtitle:
                'Explore the learning center and build confidence step by step.',
            mobile: mobile),
        const SizedBox(height: 20),
        if (mobile)
          Column(
              children: [_guideImage(), const SizedBox(height: 13), _topics()])
        else
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 3, child: _guideImage()),
            const SizedBox(width: 14),
            Expanded(flex: 2, child: _topics()),
          ]),
      ]));

  Widget _guideImage() => InkWell(
      onTap: onLearn,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(alignment: Alignment.center, children: [
          Image.asset('$_asset' 'video_guide.webp', fit: BoxFit.cover),
          Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xCC081720),
                  border: Border.all(color: _gold, width: 2)),
              child: const Icon(Icons.arrow_forward_rounded, color: _gold)),
        ]),
      ));

  Widget _topics() => _Tile(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Learning topics',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        for (final topic in const [
          'Market overview',
          'Placing your first demo trade',
          'Risk awareness',
          'Using charts & tools',
          'Reviewing trade history'
        ])
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(children: [
                const Icon(Icons.play_circle_outline, color: _gold, size: 18),
                const SizedBox(width: 9),
                Expanded(
                    child: Text(topic, style: const TextStyle(fontSize: 13))),
              ])),
        const SizedBox(height: 5),
        TextButton(
            onPressed: onLearn, child: const Text('Open learning center →')),
      ]));
}

class _AppGallery extends StatefulWidget {
  const _AppGallery({required this.mobile, required this.pad});
  final bool mobile;
  final double pad;
  @override
  State<_AppGallery> createState() => _AppGalleryState();
}

class _AppGalleryState extends State<_AppGallery> {
  final _controller = PageController(viewportFraction: 0.82);
  int _index = 0;
  static const _shots = [
    ('Markets', 'phone_markets.webp'),
    ('Trading', 'phone_trading.webp'),
    ('Portfolio', 'phone_portfolio.webp'),
    ('Learn', 'phone_learn.webp'),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.fromLTRB(widget.pad, widget.mobile ? 35 : 52,
            widget.pad, widget.mobile ? 35 : 52),
        decoration: const BoxDecoration(
            gradient:
                LinearGradient(colors: [Color(0xFF081B26), Color(0xFF0C2632)])),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _SectionTitle(
              eyebrow: 'APP EXPERIENCE',
              title: 'A Powerful Trading Experience',
              subtitle:
                  'Explore markets, chart price action, review your portfolio and learn on the go.',
              mobile: widget.mobile),
          const SizedBox(height: 17),
          if (widget.mobile) ...[
            SizedBox(
                height: 405,
                child: PageView.builder(
                    controller: _controller,
                    itemCount: _shots.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (_, i) => Column(children: [
                          Expanded(
                              child: Image.asset('$_asset${_shots[i].$2}',
                                  fit: BoxFit.contain)),
                          const SizedBox(height: 5),
                          Text(_shots[i].$1,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800)),
                        ]))),
            const SizedBox(height: 8),
            Center(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                  onPressed: _index > 0
                      ? () => _controller.previousPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut)
                      : null,
                  icon: const Icon(Icons.chevron_left)),
              Text('${_index + 1} / ${_shots.length}',
                  style: const TextStyle(color: _muted)),
              IconButton(
                  onPressed: _index < _shots.length - 1
                      ? () => _controller.nextPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut)
                      : null,
                  icon: const Icon(Icons.chevron_right)),
            ])),
          ] else
            Row(children: [
              for (final shot in _shots)
                Expanded(
                    child: Column(children: [
                  Image.asset('$_asset${shot.$2}',
                      height: 315, fit: BoxFit.contain),
                  const SizedBox(height: 4),
                  Text(shot.$1,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                ]))
            ]),
          const SizedBox(height: 8),
          const Text(
              'Illustrative product renders; screens and market values may differ in the live app.',
              style: TextStyle(color: _muted, fontSize: 11)),
        ]),
      );
}

class _Trust extends StatelessWidget {
  const _Trust({required this.mobile, required this.pad});
  final bool mobile;
  final double pad;
  @override
  Widget build(BuildContext context) {
    const items = [
      ('Practice first', 'Explore with virtual funds', 3, 1),
      ('Account tools', 'Manage profile and security', 1, 3),
      ('Risk education', 'Learn before making decisions', 4, 1),
      ('Same account', 'Use web and Android', 0, 1),
    ];
    return _Section(
        pad: pad,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _SectionTitle(
              eyebrow: 'TRUST & SECURITY',
              title: 'Trade with Confidence',
              subtitle:
                  'A focused place to practice, learn and manage your account.',
              mobile: mobile),
          const SizedBox(height: 20),
          _Grid(columns: mobile ? 2 : 4, gap: 10, children: [
            for (final item in items)
              _Tile(
                  height: mobile ? 138 : 132,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Sprite(col: item.$3, row: item.$4, size: 36),
                        const Spacer(),
                        _CardText(item.$1, item.$2),
                      ])),
          ]),
        ]));
  }
}

class _Academy extends StatelessWidget {
  const _Academy(
      {required this.mobile, required this.pad, required this.onLearn});
  final bool mobile;
  final double pad;
  final VoidCallback onLearn;
  @override
  Widget build(BuildContext context) {
    const items = [
      ('Trading basics', 'Learn the foundations of trading.', 4, 1),
      ('Technical analysis', 'Read charts and indicators.', 5, 1),
      ('Risk management', 'Understand risk before trading.', 3, 1),
      ('Market insights', 'Stay curious about global markets.', 1, 1),
      ('Beginner guides', 'Follow step-by-step learning paths.', 4, 3),
    ];
    return _Section(
        pad: pad,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _SectionTitle(
              eyebrow: 'ZETTAX ACADEMY',
              title: 'Learn, Improve and Grow',
              subtitle:
                  'Build your knowledge and trade smarter with expert concepts.',
              action: 'Explore learning →',
              onAction: onLearn,
              mobile: mobile),
          const SizedBox(height: 20),
          _Grid(columns: mobile ? 1 : 5, gap: 10, children: [
            for (final item in items)
              _Tile(
                  onTap: onLearn,
                  height: mobile ? 104 : 137,
                  child: mobile
                      ? Row(children: [
                          _Sprite(col: item.$3, row: item.$4, size: 39),
                          const SizedBox(width: 11),
                          Expanded(child: _CardText(item.$1, item.$2)),
                        ])
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                              _Sprite(col: item.$3, row: item.$4, size: 35),
                              const Spacer(),
                              _CardText(item.$1, item.$2),
                            ])),
          ]),
        ]));
  }
}

class _Community extends StatelessWidget {
  const _Community({required this.mobile, required this.pad});
  final bool mobile;
  final double pad;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding:
            EdgeInsets.fromLTRB(pad, mobile ? 40 : 58, pad, mobile ? 40 : 58),
        decoration: const BoxDecoration(
            image: DecorationImage(
                image: AssetImage('$_asset' 'mountain_community.webp'),
                fit: BoxFit.cover)),
        child: Container(
            alignment: Alignment.center,
            child: Column(children: [
              Text('Explore. Practice. Grow.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontWeight: FontWeight.w900, fontSize: mobile ? 27 : 38)),
              const SizedBox(height: 8),
              const Text('Make room for better market decisions with Zettax.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 15)),
            ])),
      );
}

class _Faq extends StatelessWidget {
  const _Faq({required this.mobile, required this.pad});
  final bool mobile;
  final double pad;
  @override
  Widget build(BuildContext context) => _Section(
      pad: pad,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _SectionTitle(
            eyebrow: 'FAQ',
            title: 'Frequently Asked Questions',
            mobile: mobile),
        const SizedBox(height: 18),
        for (final item in const [
          (
            'Is Zettax free to use?',
            'You can explore the website and practice with virtual demo funds. Review the app for current account features.'
          ),
          (
            'What markets can I explore?',
            'Zettax includes crypto, forex, stocks, commodities and indices where market data is available.'
          ),
          (
            'Is the demo balance real money?',
            'No. Demo funds are virtual and cannot be withdrawn.'
          ),
          (
            'Can I use Zettax on my phone?',
            'Yes. The site adapts to mobile screens, and the Android app is available through Google Play.'
          ),
        ])
          Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                  color: _panel,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                      side: const BorderSide(color: _edge)),
                  clipBehavior: Clip.antiAlias,
                  child: ExpansionTile(
                      title: Text(item.$1,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700)),
                      iconColor: _gold,
                      collapsedIconColor: _gold,
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      expandedAlignment: Alignment.centerLeft,
                      children: [
                        Text(item.$2,
                            style: const TextStyle(color: _muted, height: 1.45))
                      ]))),
      ]));
}

class _Footer extends StatelessWidget {
  const _Footer(
      {required this.mobile,
      required this.pad,
      required this.onDemo,
      required this.onDownload,
      required this.onLearn,
      required this.onLogin});
  final bool mobile;
  final double pad;
  final VoidCallback onDemo, onDownload, onLearn, onLogin;
  @override
  Widget build(BuildContext context) => Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(pad, 40, pad, 28),
      color: const Color(0xFF051018),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const ZettaxMark(height: 34),
          const SizedBox(width: 7),
          const Text('Zettax',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
          const Spacer(),
          if (!mobile)
            _GoldButton('Download App', Icons.download_rounded, onDownload),
        ]),
        const SizedBox(height: 13),
        const Text('Trade. Learn. Explore Markets.',
            style: TextStyle(color: _muted)),
        const SizedBox(height: 18),
        Wrap(spacing: 8, runSpacing: 4, children: [
          TextButton(onPressed: onDemo, child: const Text('Try Demo')),
          TextButton(onPressed: onLearn, child: const Text('Learn')),
          TextButton(onPressed: onLogin, child: const Text('Login')),
          TextButton(
              onPressed: () => context.push('/risk'),
              child: const Text('Risk disclosure')),
        ]),
        if (mobile) ...[
          const SizedBox(height: 10),
          SizedBox(
              width: double.infinity,
              child: _GoldButton(
                  'Download App', Icons.download_rounded, onDownload))
        ],
        const Divider(color: _edge, height: 34),
        const Text(
            'Demo funds are virtual. Market data may be delayed or sampled. Trading involves risk.',
            style: TextStyle(color: _muted, fontSize: 11, height: 1.4)),
        const SizedBox(height: 10),
        const Text('© Zettax', style: TextStyle(color: _muted, fontSize: 11)),
      ]));
}

class _Section extends StatelessWidget {
  const _Section({required this.pad, required this.child});
  final double pad;
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      Padding(padding: EdgeInsets.fromLTRB(pad, 40, pad, 42), child: child);
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(
      {required this.eyebrow,
      required this.title,
      this.subtitle,
      this.action,
      this.onAction,
      required this.mobile});
  final String eyebrow, title;
  final String? subtitle, action;
  final VoidCallback? onAction;
  final bool mobile;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _Eyebrow(eyebrow),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
              child: Text(title,
                  style: TextStyle(
                      fontSize: mobile ? 24 : 33,
                      height: 1.13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.6))),
          if (action != null && !mobile)
            TextButton(
                onPressed: onAction,
                child: Text(action!,
                    style: const TextStyle(color: _gold, fontSize: 12))),
        ]),
        if (subtitle != null) ...[
          const SizedBox(height: 5),
          Text(subtitle!,
              style: const TextStyle(color: _muted, fontSize: 13, height: 1.4))
        ],
        if (action != null && mobile)
          Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                  onPressed: onAction,
                  child: Text(action!,
                      style: const TextStyle(color: _gold, fontSize: 12)))),
      ]);
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text('•  $text  •',
      style: const TextStyle(
          color: _gold,
          fontSize: 10,
          letterSpacing: 1.3,
          fontWeight: FontWeight.w800));
}

class _Tile extends StatelessWidget {
  const _Tile({required this.child, this.height, this.onTap});
  final Widget child;
  final double? height;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
      color: _panel,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: _edge)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
          onTap: onTap,
          child: Container(
              height: height,
              padding: const EdgeInsets.all(12),
              child: child)));
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
          color: const Color(0xDA10212B),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _edge),
          boxShadow: const [
            BoxShadow(color: Color(0x77000000), blurRadius: 22)
          ]),
      child: child);
}

class _CardText extends StatelessWidget {
  const _CardText(this.title, this.detail);
  final String title, detail;
  @override
  Widget build(BuildContext context) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            Text(detail,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 11, height: 1.3, color: _muted)),
          ]);
}

class _Grid extends StatelessWidget {
  const _Grid(
      {required this.columns, required this.gap, required this.children});
  final int columns;
  final double gap;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (_, c) {
        final w = (c.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(spacing: gap, runSpacing: gap, children: [
          for (final child in children) SizedBox(width: w, child: child)
        ]);
      });
}

class _Sprite extends StatelessWidget {
  const _Sprite({required this.col, required this.row, required this.size});
  final int col, row;
  final double size;
  @override
  Widget build(BuildContext context) => ClipRect(
      child: SizedBox(
          width: size,
          height: size,
          child: Image.asset('$_asset' 'icon_sheet.webp',
              width: size,
              height: size,
              fit: BoxFit.none,
              scale: 256 / size,
              alignment: Alignment(-1 + (2 * col / 5), -1 + (2 * row / 3)))));
}

class _GoldButton extends StatelessWidget {
  const _GoldButton(this.label, this.icon, this.onTap);
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => FilledButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: FilledButton.styleFrom(
          backgroundColor: _gold,
          foregroundColor: _navy,
          minimumSize: const Size(0, 46),
          textStyle:
              const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)));
}

class _OutlineButton extends StatelessWidget {
  const _OutlineButton(this.label, this.icon, this.onTap);
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: const BorderSide(color: _gold),
          minimumSize: const Size(0, 46),
          textStyle:
              const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)));
}
