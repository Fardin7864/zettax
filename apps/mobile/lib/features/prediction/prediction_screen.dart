import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:primevest_mobile/app/design_system.dart';
import 'package:primevest_mobile/app/top_notification.dart';
import 'package:primevest_mobile/core/account/account_models.dart';
import 'package:primevest_mobile/core/api/api_contract.dart';
import 'package:primevest_mobile/core/app_providers.dart';
import 'package:primevest_mobile/core/trading/trading_models.dart';
import 'package:primevest_mobile/demo/models.dart' show MarketAsset;
import 'package:primevest_mobile/market/market_data_providers.dart';

const _featured = [
  'btc-usd',
  'eth-usd',
  'sol-usd',
  'xrp-usd',
  'ada-usd',
  'doge-usd',
  'avax-usd',
  'link-usd'
];
const _up = Color(0xFF19B996);
const _down = Color(0xFFF3485D);

class PredictionScreen extends ConsumerStatefulWidget {
  const PredictionScreen({super.key});
  @override
  ConsumerState<PredictionScreen> createState() => _PredictionScreenState();
}

class _PredictionScreenState extends ConsumerState<PredictionScreen> {
  List<MarketAsset> assets = [];
  Map<String, double> prices = {};
  List<TimedContract> contracts = [];
  String selectedId = 'btc-usd';
  String query = '';
  bool loading = true;
  bool historyLoading = false;
  bool showingHistory = false;
  String? error;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    _load();
    timer = Timer.periodic(const Duration(seconds: 30), (_) {
      _refreshPrices();
      if (showingHistory) _refreshHistory();
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final api = ref.read(marketDataApiProvider);
      final all = await api.fetchInstruments();
      final available = all
          .where((item) =>
              item.assetClass.toLowerCase() == 'crypto' &&
              _featured.contains(item.id))
          .toList()
        ..sort((a, b) =>
            _featured.indexOf(a.id).compareTo(_featured.indexOf(b.id)));
      if (!mounted) return;
      setState(() {
        assets = available;
        loading = false;
        error = null;
      });
      await Future.wait([_refreshPrices(), _refreshHistory()]);
    } catch (failure) {
      if (mounted) {
        setState(() {
          loading = false;
          error = failure is ApiFailure
              ? failure.message
              : 'Prediction markets could not be loaded.';
        });
      }
    }
  }

  Future<void> _refreshPrices() async {
    if (assets.isEmpty) return;
    final api = ref.read(marketDataApiProvider);
    final results = await Future.wait(assets.map((asset) async {
      try {
        final series = await api.fetchCandles(asset.id, '1m', limit: 10);
        return MapEntry(asset.id, series.candles.last.close);
      } catch (_) {
        return MapEntry(asset.id, double.nan);
      }
    }));
    if (!mounted) return;
    setState(() {
      for (final entry in results) {
        if (entry.value.isFinite && entry.value > 0) {
          prices[entry.key] = entry.value;
        }
      }
    });
  }

  Future<void> _refreshHistory() async {
    if (historyLoading ||
        ref.read(sessionProvider).phase != SessionPhase.authenticated) {
      return;
    }
    historyLoading = true;
    try {
      final rows = await ref
          .read(tradingRepositoryProvider)
          .timedContracts(AccountMode.demo);
      if (mounted) setState(() => contracts = rows);
    } catch (_) {
      /* The market view remains usable if history is offline. */
    } finally {
      historyLoading = false;
    }
  }

  Future<void> _openTrade(MarketAsset asset, String direction) async {
    if (ref.read(sessionProvider).phase != SessionPhase.authenticated) {
      context.push('/login');
      return;
    }
    String currentFeeRate;
    try {
      currentFeeRate =
          await ref.read(tradingRepositoryProvider).profitFeeRate();
    } catch (failure) {
      showTopNotification(
          failure is ApiFailure
              ? failure.message
              : 'Trading terms could not be loaded.',
          success: false);
      return;
    }
    if (!mounted) return;
    final accepted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _PredictionTradeSheet(
          asset: asset,
          direction: direction,
          displayPrice: prices[asset.id],
          feeRate: currentFeeRate),
    );
    if (accepted == true) {
      ref.invalidate(accountsProvider);
      await _refreshHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = assets.where((item) => item.id == selectedId).firstOrNull;
    final live = ref.watch(
        liveCandlesProvider((assetId: selectedId, interval: '1m', limit: 60)));
    final livePrice = live.valueOrNull?.candles.lastOrNull?.close;
    final account = ref
        .watch(accountsProvider)
        .valueOrNull
        ?.where((item) => item.mode == AccountMode.demo)
        .firstOrNull;
    final balance = account?.wallets
        .where((item) => item.currency == 'USD')
        .firstOrNull
        ?.available;
    final shown = assets
        .where((item) => '${item.symbol} ${item.name}'
            .toLowerCase()
            .contains(query.toLowerCase()))
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Prediction'), actions: [
        IconButton(
            onPressed: () {
              _refreshPrices();
              _refreshHistory();
            },
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh')
      ]),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(error!),
                  TextButton(onPressed: _load, child: const Text('Retry'))
                ]))
              : RefreshIndicator(
                  onRefresh: () async {
                    await _refreshPrices();
                    await _refreshHistory();
                  },
                  child: ListView(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
                      children: [
                        Container(
                            padding: const EdgeInsets.all(17),
                            decoration: BoxDecoration(
                                color: PrimeVestDesignSystem.surfaceDark,
                                borderRadius: BorderRadius.circular(18)),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('PRACTICE PREDICTIONS',
                                      style: TextStyle(
                                          color:
                                              PrimeVestDesignSystem.primaryGold,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 1.1)),
                                  const SizedBox(height: 7),
                                  const Text('Where will the market move?',
                                      style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 5),
                                  const Text(
                                      'Choose higher or lower, select an expiry, and use virtual funds. Settlement uses Zettax’s recorded market price.',
                                      style: TextStyle(
                                          color:
                                              PrimeVestDesignSystem.textMuted,
                                          height: 1.35)),
                                  const SizedBox(height: 12),
                                  Text(
                                      balance == null
                                          ? 'Sign in to use your demo balance'
                                          : 'Available demo balance  •  \$$balance',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700)),
                                ])),
                        const SizedBox(height: 14),
                        if (selected != null)
                          Card(
                              color: PrimeVestDesignSystem.surfaceDark,
                              child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(children: [
                                          Expanded(
                                              child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                Text(selected.symbol,
                                                    style: const TextStyle(
                                                        fontSize: 19,
                                                        fontWeight:
                                                            FontWeight.bold)),
                                                Text(selected.name,
                                                    style: const TextStyle(
                                                        color:
                                                            PrimeVestDesignSystem
                                                                .textMuted)),
                                              ])),
                                          Text(
                                              _price(
                                                  livePrice ??
                                                      prices[selected.id],
                                                  selected.precision),
                                              style: const TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold))
                                        ]),
                                        const SizedBox(height: 12),
                                        SizedBox(
                                            height: 110,
                                            width: double.infinity,
                                            child: live.when(
                                              data: (series) => CustomPaint(
                                                  painter: _TrendPainter(series
                                                      .candles
                                                      .map((item) => item.close)
                                                      .toList())),
                                              loading: () => const Center(
                                                  child:
                                                      CircularProgressIndicator()),
                                              error: (_, __) => const Center(
                                                  child: Text(
                                                      'Live chart unavailable')),
                                            )),
                                        const SizedBox(height: 9),
                                        const Text(
                                            'Will the price finish higher or lower than the entry price?',
                                            style: TextStyle(
                                                color: PrimeVestDesignSystem
                                                    .textMuted)),
                                        const SizedBox(height: 12),
                                        Row(children: [
                                          Expanded(
                                              child: _DirectionButton(
                                                  label: 'Higher',
                                                  color: _up,
                                                  onPressed: () => _openTrade(
                                                      selected, 'UP'))),
                                          const SizedBox(width: 10),
                                          Expanded(
                                              child: _DirectionButton(
                                                  label: 'Lower',
                                                  color: _down,
                                                  onPressed: () => _openTrade(
                                                      selected, 'DOWN')))
                                        ]),
                                      ]))),
                        const SizedBox(height: 16),
                        Row(children: [
                          ChoiceChip(
                              label: const Text('Markets'),
                              selected: !showingHistory,
                              onSelected: (_) =>
                                  setState(() => showingHistory = false)),
                          const SizedBox(width: 9),
                          ChoiceChip(
                              label: const Text('My predictions'),
                              selected: showingHistory,
                              onSelected: (_) {
                                setState(() => showingHistory = true);
                                _refreshHistory();
                              }),
                        ]),
                        const SizedBox(height: 13),
                        if (!showingHistory) ...[
                          TextField(
                              onChanged: (value) =>
                                  setState(() => query = value),
                              decoration: const InputDecoration(
                                  prefixIcon: Icon(Icons.search),
                                  hintText: 'Search markets',
                                  border: OutlineInputBorder())),
                          const SizedBox(height: 13),
                          LayoutBuilder(builder: (context, constraints) {
                            final columns = constraints.maxWidth >= 650 ? 3 : 2;
                            return GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: shown.length,
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: columns,
                                        mainAxisSpacing: 9,
                                        crossAxisSpacing: 9,
                                        childAspectRatio:
                                            columns == 2 ? 0.9 : 1.25),
                                itemBuilder: (context, index) {
                                  final asset = shown[index];
                                  return Card(
                                      color: PrimeVestDesignSystem.surfaceDark,
                                      margin: EdgeInsets.zero,
                                      child: InkWell(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          onTap: () => setState(
                                              () => selectedId = asset.id),
                                          child: Padding(
                                              padding: const EdgeInsets.all(12),
                                              child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(asset.symbol,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: const TextStyle(
                                                            fontWeight:
                                                                FontWeight
                                                                    .w800)),
                                                    const SizedBox(height: 3),
                                                    Text(asset.name,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: const TextStyle(
                                                            fontSize: 11,
                                                            color:
                                                                PrimeVestDesignSystem
                                                                    .textMuted)),
                                                    const Spacer(),
                                                    Text(
                                                        _price(prices[asset.id],
                                                            asset.precision),
                                                        style: const TextStyle(
                                                            fontSize: 17,
                                                            fontWeight:
                                                                FontWeight
                                                                    .bold)),
                                                    const SizedBox(height: 7),
                                                    const Text(
                                                        'Higher or lower at expiry?',
                                                        style: TextStyle(
                                                            fontSize: 10,
                                                            color:
                                                                PrimeVestDesignSystem
                                                                    .textMuted)),
                                                    const SizedBox(height: 8),
                                                    Row(children: [
                                                      Expanded(
                                                          child: _DirectionButton(
                                                              label: 'Up',
                                                              color: _up,
                                                              compact: true,
                                                              onPressed: () =>
                                                                  _openTrade(
                                                                      asset,
                                                                      'UP'))),
                                                      const SizedBox(width: 5),
                                                      Expanded(
                                                          child: _DirectionButton(
                                                              label: 'Down',
                                                              color: _down,
                                                              compact: true,
                                                              onPressed: () =>
                                                                  _openTrade(
                                                                      asset,
                                                                      'DOWN')))
                                                    ]),
                                                  ]))));
                                });
                          }),
                        ] else if (ref.watch(sessionProvider).phase !=
                            SessionPhase.authenticated)
                          Center(
                              child: TextButton(
                                  onPressed: () => context.push('/login'),
                                  child: const Text(
                                      'Sign in to see your predictions')))
                        else if (contracts.isEmpty)
                          const Padding(
                              padding: EdgeInsets.all(45),
                              child: Center(child: Text('No predictions yet.')))
                        else ...[
                          for (final contract in contracts)
                            _PredictionHistoryCard(
                                contract: contract,
                                symbol: assets
                                        .where((asset) =>
                                            asset.id == contract.instrumentId)
                                        .firstOrNull
                                        ?.symbol ??
                                    contract.instrumentId),
                        ],
                        const SizedBox(height: 20),
                        const Text(
                            'Practice only. Market display prices may differ from the recorded entry and expiry quotes used for settlement. No real asset is purchased.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 11,
                                color: PrimeVestDesignSystem.textMuted)),
                      ])),
    );
  }
}

String _price(double? value, int precision) => value == null || !value.isFinite
    ? '—'
    : '\$${value.toStringAsFixed(math.min(precision, 6))}';

class _DirectionButton extends StatelessWidget {
  const _DirectionButton(
      {required this.label,
      required this.color,
      required this.onPressed,
      this.compact = false});
  final String label;
  final Color color;
  final VoidCallback onPressed;
  final bool compact;
  @override
  Widget build(BuildContext context) => FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: EdgeInsets.symmetric(
              horizontal: compact ? 4 : 12, vertical: compact ? 8 : 11),
          minimumSize: const Size(0, 33)),
      child: Text(label,
          style: TextStyle(
              fontSize: compact ? 11 : 14, fontWeight: FontWeight.bold)));
}

class _TrendPainter extends CustomPainter {
  _TrendPainter(this.prices);
  final List<double> prices;
  @override
  void paint(Canvas canvas, Size size) {
    if (prices.length < 2) return;
    final low = prices.reduce(math.min);
    final high = prices.reduce(math.max);
    final span = math.max(high - low, high * 0.001);
    final path = Path();
    for (var index = 0; index < prices.length; index++) {
      final point = Offset(index * size.width / (prices.length - 1),
          size.height - 6 - (prices[index] - low) / span * (size.height - 12));
      if (index == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    final color = prices.last >= prices.first ? _up : _down;
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      oldDelegate.prices != prices;
}

class _PredictionTradeSheet extends ConsumerStatefulWidget {
  const _PredictionTradeSheet(
      {required this.asset,
      required this.direction,
      required this.displayPrice,
      required this.feeRate});
  final MarketAsset asset;
  final String direction;
  final double? displayPrice;
  final String feeRate;
  @override
  ConsumerState<_PredictionTradeSheet> createState() =>
      _PredictionTradeSheetState();
}

class _PredictionTradeSheetState extends ConsumerState<_PredictionTradeSheet> {
  final stake = TextEditingController();
  int duration = 300;
  bool submitting = false;
  @override
  void dispose() {
    stake.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final value = stake.text.trim();
    final amount = double.tryParse(value);
    if (!RegExp(r'^(?:0|[1-9]\d*)(?:\.\d{1,2})?$').hasMatch(value) ||
        amount == null ||
        amount < 0.01) {
      showTopNotification(
          'Enter a virtual stake with up to two decimal places.',
          success: false);
      return;
    }
    setState(() => submitting = true);
    try {
      if (await ref.read(tradingRepositoryProvider).pendingTimedContract() !=
          null) {
        await ref.read(tradingRepositoryProvider).retryPendingTimedContract();
      }
      await ref.read(tradingRepositoryProvider).createTimedContract(
            mode: AccountMode.demo,
            instrumentId: widget.asset.id,
            direction: widget.direction,
            investmentAmount: amount.toStringAsFixed(2),
            durationSeconds: duration,
            expectedProfitFeeRate: widget.feeRate,
          );
      if (mounted) {
        showTopNotification('Practice prediction placed.');
        Navigator.pop(context, true);
      }
    } catch (failure) {
      showTopNotification(
          failure is ApiFailure
              ? failure.message
              : 'Prediction could not be placed.',
          success: false);
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
      padding: EdgeInsets.fromLTRB(
          20, 18, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Row(children: [
              Icon(
                  widget.direction == 'UP'
                      ? Icons.trending_up
                      : Icons.trending_down,
                  color: widget.direction == 'UP' ? _up : _down),
              const SizedBox(width: 9),
              Text(
                  '${widget.asset.symbol} · ${widget.direction == 'UP' ? 'Higher' : 'Lower'}',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold))
            ]),
            const SizedBox(height: 9),
            Text(
                'Current display price: ${_price(widget.displayPrice, widget.asset.precision)}',
                style: const TextStyle(color: PrimeVestDesignSystem.textMuted)),
            const SizedBox(height: 17),
            DropdownButtonFormField<int>(
                initialValue: duration,
                decoration: const InputDecoration(labelText: 'Expiry'),
                items: const [
                  DropdownMenuItem(value: 300, child: Text('5 minutes')),
                  DropdownMenuItem(value: 900, child: Text('15 minutes')),
                  DropdownMenuItem(value: 3600, child: Text('1 hour')),
                ],
                onChanged: submitting
                    ? null
                    : (value) => setState(() => duration = value!)),
            const SizedBox(height: 12),
            TextField(
                controller: stake,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Virtual stake (USD)', prefixText: '\$ ')),
            const SizedBox(height: 14),
            const Text(
                'The entry price is recorded when you confirm. The result is determined at expiry from the recorded Zettax price source.',
                style: TextStyle(
                    fontSize: 12, color: PrimeVestDesignSystem.textMuted)),
            const SizedBox(height: 18),
            SizedBox(
                width: double.infinity,
                child: FilledButton(
                    onPressed: submitting ? null : _submit,
                    child: submitting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Confirm practice prediction'))),
          ])));
}

class _PredictionHistoryCard extends StatelessWidget {
  const _PredictionHistoryCard({required this.contract, required this.symbol});
  final TimedContract contract;
  final String symbol;
  @override
  Widget build(BuildContext context) {
    final outcome = contract.result;
    final color = outcome == 'WIN'
        ? _up
        : outcome == 'LOSS'
            ? _down
            : PrimeVestDesignSystem.textMuted;
    return Card(
        color: PrimeVestDesignSystem.surfaceDark,
        child: Padding(
            padding: const EdgeInsets.all(14),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                    child: Text(
                        '$symbol · ${contract.direction == 'UP' ? 'Higher' : 'Lower'}',
                        style: const TextStyle(fontWeight: FontWeight.bold))),
                Text(outcome,
                    style: TextStyle(color: color, fontWeight: FontWeight.bold))
              ]),
              const SizedBox(height: 8),
              Text(
                  'Stake: \$${contract.investmentAmount}   Entry: ${contract.entryPrice}',
                  style: const TextStyle(
                      fontSize: 12, color: PrimeVestDesignSystem.textMuted)),
              Text('Expires: ${contract.expiryTimestamp.toLocal()}',
                  style: const TextStyle(
                      fontSize: 12, color: PrimeVestDesignSystem.textMuted)),
              if (contract.payoutAmount != null)
                Text('Payout: \$${contract.payoutAmount}',
                    style: TextStyle(color: color)),
            ])));
  }
}
