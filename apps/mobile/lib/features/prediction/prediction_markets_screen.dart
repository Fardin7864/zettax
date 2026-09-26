import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:primevest_mobile/app/design_system.dart';
import 'package:primevest_mobile/app/top_notification.dart';
import 'package:primevest_mobile/core/account/account_models.dart';
import 'package:primevest_mobile/core/api/api_contract.dart';
import 'package:primevest_mobile/core/api/api_environment.dart';
import 'package:primevest_mobile/core/app_providers.dart';
import 'package:primevest_mobile/demo/models.dart' show MarketAsset;
import 'package:primevest_mobile/market/market_data_providers.dart';

Map<String, dynamic> _object(dynamic value) =>
    Map<String, dynamic>.from(value as Map);

String _money(dynamic value) {
  final parsed = double.tryParse(value?.toString() ?? '');
  if (parsed == null) return '—';
  return '\$${parsed.toStringAsFixed(2)}';
}

String _expiry(dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  if (date == null) return '';
  final remaining = date.difference(DateTime.now());
  if (remaining.isNegative) return 'Settling';
  if (remaining.inDays > 0) {
    return '${remaining.inDays}d ${remaining.inHours % 24}h left';
  }
  if (remaining.inHours > 0) {
    return '${remaining.inHours}h ${remaining.inMinutes % 60}m left';
  }
  return '${remaining.inMinutes}m left';
}

class PredictionMarketsScreen extends ConsumerStatefulWidget {
  const PredictionMarketsScreen({super.key});
  @override
  ConsumerState<PredictionMarketsScreen> createState() =>
      _PredictionMarketsScreenState();
}

class _PredictionMarketsScreenState
    extends ConsumerState<PredictionMarketsScreen> {
  final questions = <Map<String, dynamic>>[];
  final positions = <Map<String, dynamic>>[];
  Map<String, dynamic> availability = {};
  String mode = 'DEMO';
  String status = 'OPEN';
  String? cursor;
  String? error;
  bool loading = true;
  bool loadingMore = false;
  bool showingPositions = false;
  io.Socket? socket;
  Timer? refresh;

  @override
  void initState() {
    super.initState();
    _load();
    _loadAvailability();
    final endpoint = ApiEnvironment.baseUri
        .replace(path: '/prediction', query: null, fragment: null);
    socket = io.io(
        endpoint.toString(),
        io.OptionBuilder()
            .setTransports(['websocket'])
            .disableAutoConnect()
            .enableReconnection()
            .setReconnectionDelay(1000)
            .setReconnectionDelayMax(30000)
            .build()
          ..addAll({'forceNew': true, 'multiplex': false}));
    socket!.on('prediction:created', (_) => _load());
    socket!.on('prediction:changed', (_) {
      _load();
      if (showingPositions) _loadPositions();
    });
    socket!.connect();
    refresh = Timer.periodic(const Duration(seconds: 20), (_) {
      _load();
      if (showingPositions) _loadPositions();
    });
  }

  @override
  void dispose() {
    socket?.dispose();
    refresh?.cancel();
    super.dispose();
  }

  Future<void> _loadAvailability() async {
    try {
      final response = await ref
          .read(apiClientProvider)
          .get('/prediction/availability', _object, authenticated: false);
      if (mounted) setState(() => availability = response.data);
    } catch (_) {
      // Questions can still be browsed when availability is temporarily offline.
    }
  }

  Future<void> _load({bool more = false}) async {
    if (more && (loadingMore || cursor == null)) return;
    if (more) setState(() => loadingMore = true);
    try {
      final response = await ref.read(apiClientProvider).get(
          '/prediction/questions', _object,
          authenticated: false,
          queryParameters: {'status': status, if (more) 'cursor': cursor});
      if (!mounted) return;
      setState(() {
        final incoming = (response.data['items'] as List).map(_object).toList();
        if (!more) questions.clear();
        final known = questions.map((item) => item['id']).toSet();
        questions.addAll(incoming.where((item) => !known.contains(item['id'])));
        cursor = response.data['nextCursor']?.toString();
        loading = false;
        loadingMore = false;
        error = null;
      });
    } catch (failure) {
      if (!mounted) return;
      setState(() {
        error = failure is ApiFailure
            ? failure.message
            : 'Prediction questions could not be loaded.';
        loading = false;
        loadingMore = false;
      });
    }
  }

  Future<void> _loadPositions() async {
    if (ref.read(sessionProvider).phase != SessionPhase.authenticated) return;
    try {
      final response = await ref.read(apiClientProvider).get(
          '/prediction/mine', (value) => (value as List).map(_object).toList());
      if (mounted) {
        setState(() {
          positions
            ..clear()
            ..addAll(response.data);
        });
      }
    } catch (failure) {
      showTopNotification(
          failure is ApiFailure
              ? failure.message
              : 'Positions could not be loaded.',
          success: false);
    }
  }

  Future<void> _create() async {
    if (ref.read(sessionProvider).phase != SessionPhase.authenticated) {
      context.push('/login');
      return;
    }
    final created = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => const _CreateQuestionSheet());
    if (created == true) _load();
  }

  Future<void> _vote(Map<String, dynamic> question, String side) async {
    if (ref.read(sessionProvider).phase != SessionPhase.authenticated) {
      context.push('/login');
      return;
    }
    final accepted = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _PredictionVoteSheet(
            question: question,
            side: side,
            mode: mode,
            realAvailable: availability['real'] == true));
    if (accepted == true) {
      ref.invalidate(accountsProvider);
      _load();
      _loadPositions();
    }
  }

  @override
  Widget build(BuildContext context) {
    final signedIn =
        ref.watch(sessionProvider).phase == SessionPhase.authenticated;
    final selectedAccount = ref
        .watch(accountsProvider)
        .valueOrNull
        ?.where((item) =>
            item.mode == (mode == 'DEMO' ? AccountMode.demo : AccountMode.real))
        .firstOrNull;
    final balance = selectedAccount?.wallets
        .where((item) => item.currency == 'USD')
        .firstOrNull
        ?.available;
    return Scaffold(
      appBar: AppBar(title: const Text('Prediction Markets'), actions: [
        IconButton(
            tooltip: 'Create question',
            onPressed: _create,
            icon: const Icon(Icons.add_circle_outline)),
      ]),
      body: RefreshIndicator(
        onRefresh: () async {
          await _load();
          await _loadPositions();
        },
        child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 30),
            children: [
              Container(
                padding: const EdgeInsets.all(17),
                decoration: BoxDecoration(
                    color: PrimeVestDesignSystem.surfaceDark,
                    borderRadius: BorderRadius.circular(18)),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('YOUR CALL ON THE MARKET',
                          style: TextStyle(
                              color: PrimeVestDesignSystem.primaryGold,
                              fontSize: 11,
                              letterSpacing: 1.1,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      const Text('Make a prediction. See the result.',
                          style: TextStyle(
                              fontSize: 22, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 5),
                      const Text(
                          'Create a price question or take a Yes/No position. Questions settle from an archived market price at the stated UTC expiry.',
                          style: TextStyle(
                              color: PrimeVestDesignSystem.textMuted,
                              height: 1.4)),
                      const SizedBox(height: 15),
                      Wrap(spacing: 8, children: [
                        ChoiceChip(
                            label: const Text('Virtual'),
                            selected: mode == 'DEMO',
                            onSelected: (_) => setState(() => mode = 'DEMO')),
                        ChoiceChip(
                            label: const Text('Real money'),
                            selected: mode == 'REAL',
                            onSelected: (_) => setState(() => mode = 'REAL')),
                      ]),
                      const SizedBox(height: 10),
                      Text(
                          signedIn
                              ? 'Available ${balance == null ? '—' : _money(balance)}'
                              : 'Sign in to join a question.',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      if (mode == 'REAL' && availability['real'] != true)
                        const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                                'Real-money predictions are pending release approval. You can explore questions and practice with virtual funds.',
                                style: TextStyle(
                                    color: PrimeVestDesignSystem.textMuted))),
                    ]),
              ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                    child: FilledButton.icon(
                        onPressed: _create,
                        icon: const Icon(Icons.add),
                        label: const Text('Create question'))),
                const SizedBox(width: 8),
                OutlinedButton(
                    onPressed: () => context.push('/prediction/direction'),
                    child: const Text('Price direction')),
              ]),
              const SizedBox(height: 18),
              Wrap(spacing: 8, runSpacing: 8, children: [
                ChoiceChip(
                    label: const Text('Open'),
                    selected: !showingPositions && status == 'OPEN',
                    onSelected: (_) {
                      setState(() {
                        showingPositions = false;
                        status = 'OPEN';
                        loading = true;
                      });
                      _load();
                    }),
                ChoiceChip(
                    label: const Text('Resolved'),
                    selected: !showingPositions && status == 'SETTLED',
                    onSelected: (_) {
                      setState(() {
                        showingPositions = false;
                        status = 'SETTLED';
                        loading = true;
                      });
                      _load();
                    }),
                ChoiceChip(
                    label: const Text('My positions'),
                    selected: showingPositions,
                    onSelected: (_) {
                      setState(() => showingPositions = true);
                      _loadPositions();
                    }),
              ]),
              const SizedBox(height: 12),
              if (showingPositions)
                if (!signedIn)
                  Center(
                      child: TextButton(
                          onPressed: () => context.push('/login'),
                          child: const Text('Sign in to view positions')))
                else if (positions.isEmpty)
                  const Padding(
                      padding: EdgeInsets.all(30),
                      child: Center(child: Text('No positions yet.')))
                else
                  ...positions.map(_positionCard)
              else if (loading)
                const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: CircularProgressIndicator()))
              else if (error != null && questions.isEmpty)
                Center(
                    child: TextButton(
                        onPressed: () => _load(), child: Text(error!)))
              else if (questions.isEmpty)
                const Padding(
                    padding: EdgeInsets.all(30),
                    child: Center(
                        child: Text('No questions yet. Create the first one.')))
              else ...[
                ...questions.map(_questionCard),
                if (cursor != null)
                  Center(
                      child: TextButton(
                          onPressed:
                              loadingMore ? null : () => _load(more: true),
                          child: Text(loadingMore
                              ? 'Loading…'
                              : 'Load more questions'))),
              ],
            ]),
      ),
    );
  }

  Widget _questionCard(Map<String, dynamic> question) {
    final yes =
        (question[mode == 'DEMO' ? 'demoYesPoolShare' : 'realYesPoolShare']
                    as num?)
                ?.toDouble() ??
            50;
    final expiry = DateTime.tryParse(question['expiresAt']?.toString() ?? '');
    final open = question['status'] == 'OPEN' &&
        expiry != null &&
        expiry.isAfter(DateTime.now());
    final target = _money(question['targetPrice']);
    final title =
        'Will ${question['symbol']} be ${question['condition'] == 'ABOVE' ? 'above' : 'below'} $target at expiry?';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: PrimeVestDesignSystem.surfaceDark,
      child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                    child: Text(
                        '${question['creator']} · ${question['symbol']}',
                        style: const TextStyle(
                            color: PrimeVestDesignSystem.textMuted,
                            fontSize: 12))),
                Text(
                    question['status'] == 'SETTLED'
                        ? 'Resolved'
                        : _expiry(question['expiresAt']),
                    style: const TextStyle(
                        color: PrimeVestDesignSystem.primaryGold,
                        fontSize: 12)),
              ]),
              const SizedBox(height: 9),
              Text(title,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(
                  'Reference ${_money(question['referencePrice'])} · ${question['referenceSource']}',
                  style: const TextStyle(
                      color: PrimeVestDesignSystem.textMuted, fontSize: 11)),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                  value: yes / 100,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(8),
                  color: PrimeVestDesignSystem.positive,
                  backgroundColor: PrimeVestDesignSystem.negative),
              const SizedBox(height: 6),
              const Text('Current pool split',
                  style: TextStyle(
                      fontSize: 11, color: PrimeVestDesignSystem.textMuted)),
              const SizedBox(height: 3),
              Row(children: [
                Expanded(
                    child: Text('Yes stake ${yes.toStringAsFixed(1)}%',
                        style: const TextStyle(
                            color: PrimeVestDesignSystem.positive))),
                Text('No stake ${(100 - yes).toStringAsFixed(1)}%',
                    style:
                        const TextStyle(color: PrimeVestDesignSystem.negative)),
              ]),
              const SizedBox(height: 5),
              Text(
                  'Pool ${_money(question[mode == 'DEMO' ? 'yesDemoPool' : 'yesRealPool'])} Yes · ${_money(question[mode == 'DEMO' ? 'noDemoPool' : 'noRealPool'])} No',
                  style: const TextStyle(
                      fontSize: 11, color: PrimeVestDesignSystem.textMuted)),
              if (question['status'] == 'SETTLED') ...[
                const SizedBox(height: 10),
                Text(
                    'Outcome ${question['outcome']} · observed ${_money(question['settlementPrice'])}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ] else if (open) ...[
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                      child: FilledButton(
                          onPressed: () => _vote(question, 'YES'),
                          child: const Text('Yes'))),
                  const SizedBox(width: 9),
                  Expanded(
                      child: OutlinedButton(
                          onPressed: () => _vote(question, 'NO'),
                          child: const Text('No'))),
                ]),
              ],
            ],
          )),
    );
  }

  Widget _positionCard(Map<String, dynamic> position) {
    final question = _object(position['question']);
    return Card(
        color: PrimeVestDesignSystem.surfaceDark,
        child: ListTile(
          title: Text(
              '${question['symbol']} ${question['condition'] == 'ABOVE' ? 'above' : 'below'} ${_money(question['targetPrice'])}'),
          subtitle: Text(
              '${position['accountMode']} · ${position['side']} · stake ${_money(position['stake'])}'),
          trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(position['result']?.toString() ?? 'PENDING'),
                Text(
                    position['payoutAmount'] == null
                        ? _expiry(question['expiresAt'])
                        : _money(position['payoutAmount']),
                    style: const TextStyle(
                        color: PrimeVestDesignSystem.primaryGold)),
              ]),
        ));
  }
}

class _CreateQuestionSheet extends ConsumerStatefulWidget {
  const _CreateQuestionSheet();
  @override
  ConsumerState<_CreateQuestionSheet> createState() =>
      _CreateQuestionSheetState();
}

class _CreateQuestionSheetState extends ConsumerState<_CreateQuestionSheet> {
  final target = TextEditingController();
  List<MarketAsset> assets = [];
  String? instrumentId;
  String condition = 'ABOVE';
  int expiryMinutes = 60;
  bool loading = true;
  bool sending = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _loadAssets();
  }

  @override
  void dispose() {
    target.dispose();
    super.dispose();
  }

  Future<void> _loadAssets() async {
    try {
      final all = await ref.read(marketDataApiProvider).fetchInstruments();
      final crypto = all
          .where((asset) => asset.assetClass.toLowerCase() == 'crypto')
          .toList();
      if (!mounted) return;
      setState(() {
        assets = crypto;
        instrumentId = crypto.firstOrNull?.id;
        loading = false;
      });
      if (instrumentId != null) _suggestTarget(instrumentId!);
    } catch (failure) {
      if (mounted) {
        setState(() {
          loading = false;
          error = failure is ApiFailure
              ? failure.message
              : 'Markets could not be loaded.';
        });
      }
    }
  }

  Future<void> _suggestTarget(String assetId) async {
    try {
      final series = await ref
          .read(marketDataApiProvider)
          .fetchCandles(assetId, '1m', limit: 10);
      if (!mounted || instrumentId != assetId) return;
      final precision =
          assets.where((item) => item.id == assetId).first.precision;
      target.text = series.candles.last.close.toStringAsFixed(precision);
    } catch (_) {
      // A user can still enter the target manually.
    }
  }

  Future<void> _create() async {
    if (sending || instrumentId == null) return;
    final price = double.tryParse(target.text.trim());
    if (price == null || !price.isFinite || price <= 0) {
      showTopNotification('Enter a valid target price.', success: false);
      return;
    }
    setState(() => sending = true);
    try {
      await ref.read(apiClientProvider).post(
          '/prediction/questions',
          {
            'instrumentId': instrumentId,
            'condition': condition,
            'targetPrice': target.text.trim(),
            'expiresAt': DateTime.now()
                .toUtc()
                .add(Duration(minutes: expiryMinutes))
                .toIso8601String(),
          },
          _object);
      if (mounted) {
        showTopNotification('Prediction question created.');
        Navigator.pop(context, true);
      }
    } catch (failure) {
      showTopNotification(
          failure is ApiFailure
              ? failure.message
              : 'Question could not be created.',
          success: false);
    } finally {
      if (mounted) setState(() => sending = false);
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
            const Text('Create a price question',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text(
                'Everyone sees the same target and expiry. Zettax checks the archived price to resolve it.',
                style: TextStyle(color: PrimeVestDesignSystem.textMuted)),
            const SizedBox(height: 18),
            if (loading)
              const Center(child: CircularProgressIndicator())
            else if (error != null)
              Text(error!)
            else ...[
              DropdownButtonFormField<String>(
                initialValue: instrumentId,
                decoration: const InputDecoration(labelText: 'Market'),
                items: assets
                    .map((asset) => DropdownMenuItem(
                        value: asset.id, child: Text(asset.symbol)))
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => instrumentId = value);
                  _suggestTarget(value);
                },
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 8, children: [
                ChoiceChip(
                    label: const Text('Above'),
                    selected: condition == 'ABOVE',
                    onSelected: (_) => setState(() => condition = 'ABOVE')),
                ChoiceChip(
                    label: const Text('Below'),
                    selected: condition == 'BELOW',
                    onSelected: (_) => setState(() => condition = 'BELOW')),
              ]),
              const SizedBox(height: 12),
              TextField(
                  controller: target,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Target price (USD)', prefixText: '\$ ')),
              const SizedBox(height: 14),
              const Text('Time until expiry',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              Wrap(spacing: 7, runSpacing: 5, children: [
                for (final item in [
                  (15, '15m'),
                  (60, '1h'),
                  (1440, '1d'),
                  (10080, '7d')
                ])
                  ChoiceChip(
                      label: Text(item.$2),
                      selected: expiryMinutes == item.$1,
                      onSelected: (_) =>
                          setState(() => expiryMinutes = item.$1)),
              ]),
              const SizedBox(height: 17),
              SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                      onPressed: sending ? null : _create,
                      child: Text(sending ? 'Creating…' : 'Create question'))),
            ],
          ],
        )),
      );
}

class _PredictionVoteSheet extends ConsumerStatefulWidget {
  const _PredictionVoteSheet(
      {required this.question,
      required this.side,
      required this.mode,
      required this.realAvailable});
  final Map<String, dynamic> question;
  final String side;
  final String mode;
  final bool realAvailable;
  @override
  ConsumerState<_PredictionVoteSheet> createState() =>
      _PredictionVoteSheetState();
}

class _PredictionVoteSheetState extends ConsumerState<_PredictionVoteSheet> {
  final stake = TextEditingController();
  late final requestKey =
      'prediction:${DateTime.now().microsecondsSinceEpoch}:${Random.secure().nextInt(1 << 31)}';
  bool sending = false;

  @override
  void dispose() {
    stake.dispose();
    super.dispose();
  }

  double? _estimatedPayout() {
    final amount = double.tryParse(stake.text.trim());
    if (amount == null || amount <= 0) return null;
    final prefix = widget.side == 'YES' ? 'yes' : 'no';
    final other = widget.side == 'YES' ? 'no' : 'yes';
    final suffix = widget.mode == 'DEMO' ? 'DemoPool' : 'RealPool';
    final samePool =
        double.tryParse(widget.question['$prefix$suffix']?.toString() ?? '') ??
            0;
    final oppositePool =
        double.tryParse(widget.question['$other$suffix']?.toString() ?? '') ??
            0;
    return amount + oppositePool * amount / (samePool + amount);
  }

  Future<void> _place() async {
    if (sending || (widget.mode == 'REAL' && !widget.realAvailable)) return;
    final value = stake.text.trim();
    final amount = double.tryParse(value);
    final minimum = widget.mode == 'REAL' ? 10 : 0.01;
    if (!RegExp(r'^(?:0|[1-9]\d*)(?:\.\d{1,2})?$').hasMatch(value) ||
        amount == null ||
        amount < minimum ||
        amount > 100000) {
      showTopNotification(
          'Enter a stake from ${_money(minimum)} to \$100,000.00 with up to two decimals.',
          success: false);
      return;
    }
    setState(() => sending = true);
    try {
      await ref.read(apiClientProvider).post(
          '/prediction/questions/${widget.question['id']}/positions',
          {
            'accountMode': widget.mode,
            'side': widget.side,
            'stake': value,
          },
          _object,
          idempotencyKey: requestKey,
          receiveTimeout: const Duration(seconds: 45));
      if (mounted) {
        showTopNotification('Prediction position placed.');
        Navigator.pop(context, true);
      }
    } catch (failure) {
      showTopNotification(
          failure is ApiFailure
              ? failure.message
              : 'Position could not be placed. Retry keeps the same request key.',
          success: false);
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final payout = _estimatedPayout();
    return Padding(
        padding: EdgeInsets.fromLTRB(
            20, 18, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(
                  '${widget.side == 'YES' ? 'Yes' : 'No'} · ${widget.question['symbol']}',
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 7),
              Text(
                  'Target ${_money(widget.question['targetPrice'])} · ${_expiry(widget.question['expiresAt'])}'),
              const SizedBox(height: 10),
              Text(
                  widget.mode == 'DEMO'
                      ? 'Virtual account'
                      : 'Real-money account',
                  style: const TextStyle(
                      color: PrimeVestDesignSystem.primaryGold,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 14),
              TextField(
                  controller: stake,
                  onChanged: (_) => setState(() {}),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Stake (USD)', prefixText: '\$ ')),
              const SizedBox(height: 10),
              Text(
                  payout == null
                      ? 'Enter a stake to see an estimate.'
                      : 'Estimated return if correct: ${_money(payout)}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text(
                  'Pool returns change when other people join. The final winning side splits the losing side’s stakes. If nobody chose the winning side, all stakes are refunded.',
                  style: TextStyle(
                      color: PrimeVestDesignSystem.textMuted, height: 1.35)),
              if (widget.mode == 'REAL' && !widget.realAvailable) ...[
                const SizedBox(height: 10),
                const Text(
                    'Real-money participation is pending release approval.',
                    style: TextStyle(color: PrimeVestDesignSystem.negative)),
              ],
              const SizedBox(height: 18),
              SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                      onPressed: sending ||
                              (widget.mode == 'REAL' && !widget.realAvailable)
                          ? null
                          : _place,
                      child: Text(sending
                          ? 'Placing…'
                          : 'Place ${widget.side} position'))),
            ])));
  }
}
