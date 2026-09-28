import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:primevest_mobile/core/app_providers.dart';
import 'package:primevest_mobile/core/api/api_environment.dart';
import 'package:primevest_mobile/app/top_notification.dart';
import 'package:primevest_mobile/demo/providers.dart';
import 'package:primevest_mobile/market/market_data_providers.dart';
import 'package:primevest_mobile/features/shared/live_trade_chart.dart';
import 'package:primevest_mobile/features/shared/ohlc_chart.dart';
import 'package:primevest_mobile/features/predictions/prediction_repository.dart';

String predictionTitle(PredictionRow q) =>
    "Will ${q['symbol']} be ${q['condition'] == 'ABOVE' ? 'above' : 'below'} \$${q['targetPrice']}?";
double predictionNumber(dynamic value) => double.tryParse('$value') ?? 0;
String predictionMoney(dynamic value) =>
    '\$${predictionNumber(value).toStringAsFixed(2)}';
String predictionStatus(PredictionRow q) {
  if (q['status'] == 'OPEN' &&
      DateTime.parse(q['expiresAt'] as String).isBefore(DateTime.now())) {
    return 'Awaiting result';
  }
  return q['status'] == 'OPEN'
      ? 'Open'
      : q['status'] == 'CANCELLED'
          ? 'Refunded'
          : 'Resolved · ${q['outcome']}';
}

class PredictionsScreen extends ConsumerStatefulWidget {
  const PredictionsScreen({super.key, this.active = true});
  final bool active;
  @override
  ConsumerState<PredictionsScreen> createState() => _PredictionsScreenState();
}

class _PredictionsScreenState extends ConsumerState<PredictionsScreen> {
  final search = TextEditingController();
  List<PredictionRow> rows = [];
  String tab = 'Explore', sort = 'NEWEST', source = '', status = 'OPEN';
  String? cursor, error;
  bool loading = false, loaded = false;
  bool queuedReload = false;
  Timer? poll, debounce;
  io.Socket? socket;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    final uri = ApiEnvironment.baseUri;
    socket = io.io(
        '${uri.origin}/prediction',
        io.OptionBuilder()
            .setTransports(['websocket'])
            .disableAutoConnect()
            .build());
    for (final event in [
      'connect',
      'prediction:sync',
      'prediction:created',
      'prediction:changed'
    ]) {
      socket!.on(event, (_) {
        if (widget.active) _load(quiet: true);
      });
    }
    if (widget.active) socket!.connect();
    poll = Timer.periodic(const Duration(seconds: 15), (_) {
      if (widget.active) _load(quiet: true);
    });
    if (widget.active) Future.microtask(_load);
  }

  @override
  void didUpdateWidget(covariant PredictionsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      socket?.connect();
      _load();
    }
    if (!widget.active) {
      socket?.disconnect();
    }
  }

  @override
  void dispose() {
    search.dispose();
    poll?.cancel();
    debounce?.cancel();
    socket?.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false, bool quiet = false}) async {
    if (!mounted) return;
    if (loading) {
      queuedReload = true;
      return;
    }
    final authenticated =
        ref.read(sessionProvider).phase == SessionPhase.authenticated;
    if (tab != 'Explore' && tab != 'Results' && !authenticated) {
      setState(() {
        rows = [];
        loaded = true;
        error = 'Sign in to see your predictions.';
      });
      return;
    }
    final revision = generation;
    setState(() {
      loading = true;
      if (!quiet) error = null;
    });
    try {
      final path = tab == 'My predictions'
          ? 'mine'
          : tab == 'Created by me'
              ? 'created'
              : 'questions';
      final query = <String, dynamic>{
        if (more && cursor != null) 'cursor': cursor,
        if (tab != 'My predictions') ...{
          if (search.text.trim().isNotEmpty) 'search': search.text.trim(),
          'sort': sort,
          if (source.isNotEmpty && tab != 'Created by me') 'source': source,
          if (tab == 'Results')
            'status': 'SETTLED'
          else if (status.isNotEmpty)
            'status': status,
        }
      };
      var data = await ref.read(predictionRepositoryProvider).read(path,
          public: tab == 'Explore' || tab == 'Results', query: query);
      final incoming = (data['items'] as List).map(predictionObject).toList();
      // Refresh every loaded page, not just page one, without collapsing history.
      while (quiet &&
          !more &&
          incoming.length < rows.length &&
          data['nextCursor'] != null) {
        data = await ref.read(predictionRepositoryProvider).read(path,
            public: tab == 'Explore' || tab == 'Results',
            query: {...query, 'cursor': data['nextCursor']});
        incoming.addAll((data['items'] as List).map(predictionObject));
      }
      if (mounted && generation == revision) {
        setState(() {
          rows = more
              ? [
                  ...rows,
                  ...incoming.where((q) => !rows.any((r) => r['id'] == q['id']))
                ]
              : incoming;
          cursor = data['nextCursor'] as String?;
          loaded = true;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
      if (mounted && queuedReload) {
        queuedReload = false;
        unawaited(_load(quiet: true));
      }
    }
  }

  Future<void> _create() async {
    if (ref.read(sessionProvider).phase != SessionPhase.authenticated) {
      context.push('/login');
      return;
    }
    await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const CreatePredictionScreen()));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(sessionProvider, (_, __) {
      if (widget.active) _load();
    });
    return RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Row(children: [
            const Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('Your market insight. Your call.',
                      style:
                          TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
                  SizedBox(height: 6),
                  Text(
                      'Predict crypto prices with demo USD. No real-money stakes.',
                      style: TextStyle(color: Colors.white60)),
                ])),
            IconButton.filled(
                tooltip: 'Create prediction',
                onPressed: _create,
                icon: const Icon(Icons.add))
          ]),
          const SizedBox(height: 16),
          SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final value in [
                  'Explore',
                  'My predictions',
                  'Created by me',
                  'Results'
                ])
                  Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                          label: Text(value),
                          selected: tab == value,
                          onSelected: (_) {
                            setState(() {
                              tab = value;
                              rows = [];
                              cursor = null;
                              loaded = false;
                              generation++;
                            });
                            _load();
                          }))
              ])),
          if (tab != 'My predictions') ...[
            const SizedBox(height: 12),
            TextField(
                controller: search,
                maxLength: 80,
                decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search crypto markets',
                    counterText: ''),
                onChanged: (_) {
                  debounce?.cancel();
                  debounce =
                      Timer(const Duration(milliseconds: 400), () => _load());
                }),
            Wrap(spacing: 12, children: [
              DropdownButton<String>(
                  value: sort,
                  items: const [
                    DropdownMenuItem(value: 'NEWEST', child: Text('Newest')),
                    DropdownMenuItem(
                        value: 'ENDING', child: Text('Ending soon')),
                    DropdownMenuItem(
                        value: 'POPULAR', child: Text('Most participants'))
                  ],
                  onChanged: (v) {
                    setState(() => sort = v!);
                    _load();
                  }),
              if (tab == 'Explore')
                DropdownButton<String>(
                    value: source,
                    items: const [
                      DropdownMenuItem(value: '', child: Text('All creators')),
                      DropdownMenuItem(
                          value: 'PLATFORM', child: Text('Zettax')),
                      DropdownMenuItem(value: 'MEMBERS', child: Text('Members'))
                    ],
                    onChanged: (v) {
                      setState(() => source = v!);
                      _load();
                    }),
              if (tab != 'Results')
                DropdownButton<String>(
                    value: status,
                    items: const [
                      DropdownMenuItem(value: '', child: Text('All states')),
                      DropdownMenuItem(value: 'OPEN', child: Text('Open')),
                      DropdownMenuItem(
                          value: 'CLOSED', child: Text('Awaiting result')),
                      DropdownMenuItem(
                          value: 'CANCELLED', child: Text('Refunded'))
                    ],
                    onChanged: (v) {
                      setState(() => status = v!);
                      _load();
                    }),
            ]),
          ],
          FutureBuilder<PredictionRow?>(
              future: ref.read(predictionRepositoryProvider).pending(),
              builder: (_, pending) => pending.data == null
                  ? const SizedBox.shrink()
                  : Card(
                      child: ListTile(
                          title: const Text(
                              'Previous request needs reconciliation'),
                          subtitle: const Text(
                              'Retry safely using the original request key.'),
                          trailing: TextButton(
                              onPressed: () async {
                                try {
                                  await ref
                                      .read(predictionRepositoryProvider)
                                      .retry();
                                  if (mounted) {
                                    ref.invalidate(accountsProvider);
                                    _load();
                                  }
                                } catch (e) {
                                  showTopNotification('$e');
                                }
                              },
                              child: const Text('Retry'))))),
          if (error != null)
            Card(
                child: ListTile(
                    title: Text(error!),
                    trailing: IconButton(
                        onPressed: _load, icon: const Icon(Icons.refresh)))),
          if (loading) const LinearProgressIndicator(),
          if (loaded && rows.isEmpty && error == null)
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(
                    child: Text(
                        'No predictions here yet. Create the first one.'))),
          for (final row in rows)
            PredictionCard(
                question: tab == 'My predictions'
                    ? predictionObject(row['question'])
                    : row,
                position: tab == 'My predictions' ? row : null,
                onTap: () async {
                  final q = tab == 'My predictions'
                      ? predictionObject(row['question'])
                      : row;
                  await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) =>
                          PredictionDetailScreen(id: q['id'] as String)));
                  if (mounted) _load();
                }),
          if (cursor != null)
            TextButton(
                onPressed: loading ? null : () => _load(more: true),
                child: const Text('Load more')),
          const SizedBox(height: 20),
          const Text(
              'YES/NO percentages represent stake allocation, not market probability. Returns depend on the final pool. Stakes remain locked until settlement; unavailable expiry prices are refunded after 24 hours.',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
        ]));
  }
}

class PredictionCard extends StatelessWidget {
  const PredictionCard(
      {super.key, required this.question, required this.onTap, this.position});
  final PredictionRow question;
  final PredictionRow? position;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final q = question, p = position;
    final share = predictionNumber(q['demoYesPoolShare']) / 100;
    final expiry = DateTime.parse(q['expiresAt'] as String).toLocal();
    final avatar = q['creatorAvatarUrl'] as String?;
    return Card(
        margin: const EdgeInsets.symmetric(vertical: 7),
        child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        CircleAvatar(
                            radius: 14,
                            backgroundImage: avatar == null
                                ? null
                                : NetworkImage(
                                    '${ApiEnvironment.baseUri}$avatar'),
                            child: avatar == null
                                ? const Icon(Icons.person, size: 18)
                                : null),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text('${q['creator']}',
                                maxLines: 2, overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: 8),
                        Flexible(
                            child: Text(predictionStatus(q),
                                textAlign: TextAlign.right,
                                style:
                                    const TextStyle(color: Color(0xFFF4C35B))))
                      ]),
                      const SizedBox(height: 12),
                      Text(predictionTitle(q),
                          style: const TextStyle(
                              fontSize: 19, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Text(
                          'Expires ${expiry.toString().substring(0, 16)} · ${q['participantCount']} participants',
                          style: const TextStyle(color: Colors.white60)),
                      const SizedBox(height: 14),
                      ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                              value: share,
                              minHeight: 7,
                              backgroundColor: const Color(0xFFDD5465),
                              color: const Color(0xFF15B892))),
                      const SizedBox(height: 8),
                      Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          spacing: 12,
                          runSpacing: 6,
                          children: [
                            Text('YES ${(share * 100).toStringAsFixed(1)}%'),
                            Text(
                                'Pool ${predictionMoney(predictionNumber(q['yesDemoPool']) + predictionNumber(q['noDemoPool']))}'),
                            Text(
                                'NO ${(100 - share * 100).toStringAsFixed(1)}%')
                          ]),
                      if (p != null)
                        Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                                "${p['side']} · Stake ${predictionMoney(p['stake'])} · ${p['result']}${p['payoutAmount'] == null ? '' : ' · Returned ${predictionMoney(p['payoutAmount'])}'}")),
                    ]))));
  }
}

class PredictionDetailScreen extends ConsumerStatefulWidget {
  const PredictionDetailScreen({super.key, required this.id});
  final String id;
  @override
  ConsumerState<PredictionDetailScreen> createState() =>
      _PredictionDetailState();
}

class _PredictionDetailState extends ConsumerState<PredictionDetailScreen> {
  PredictionRow? q;
  List<PredictionRow> ownPositions = [];
  bool reading = false;
  String? error;
  String side = 'YES', interval = '1m';
  final stake = TextEditingController(text: '10.00');
  Timer? timer;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    _load();
    timer = Timer.periodic(const Duration(seconds: 5), (_) => _load());
  }

  @override
  void dispose() {
    timer?.cancel();
    stake.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (reading) return;
    reading = true;
    try {
      final value = await ref
          .read(predictionRepositoryProvider)
          .read('questions/${widget.id}', public: true);
      if (mounted) {
        setState(() {
          q = value;
          error = null;
        });
      }
      if (ref.read(sessionProvider).phase == SessionPhase.authenticated) {
        final positions = await ref
            .read(predictionRepositoryProvider)
            .read('questions/${widget.id}/mine');
        if (mounted) {
          setState(() => ownPositions =
              (positions['items'] as List).map(predictionObject).toList());
        }
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      reading = false;
    }
  }

  Future<void> _place() async {
    if (ref.read(sessionProvider).phase != SessionPhase.authenticated) {
      context.push('/login');
      return;
    }
    final amount = double.tryParse(stake.text);
    if (amount == null ||
        amount < .01 ||
        amount > 100000 ||
        !RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(stake.text)) {
      showTopNotification(
          'Enter a stake from \$0.01 to \$100,000 with up to two decimals.');
      return;
    }
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
                title: Text('Predict $side'),
                content: Text(
                    '${predictionMoney(amount)} demo USD will be locked until settlement. Estimated returns can change as others join. No early cash-out.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Confirm prediction'))
                ]));
    if (confirmed != true || !mounted) return;
    setState(() => busy = true);
    try {
      await ref.read(predictionRepositoryProvider).submit(
          'questions/${widget.id}/positions', {
        'accountMode': 'DEMO',
        'side': side,
        'stake': amount.toStringAsFixed(2)
      });
      ref.invalidate(accountsProvider);
      showTopNotification('Prediction placed. Your demo stake is locked.',
          success: true);
      await _load();
    } catch (e) {
      showTopNotification('$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final question = q;
    final authenticated =
        ref.watch(sessionProvider).phase == SessionPhase.authenticated;
    return Scaffold(
        appBar: AppBar(title: const Text('Prediction'), actions: [
          IconButton(
              tooltip: 'Share prediction',
              onPressed: () => SharePlus.instance.share(ShareParams(
                  text: 'https://zettax.app/predictions/${widget.id}')),
              icon: const Icon(Icons.share_outlined))
        ]),
        body: question == null
            ? Center(
                child: error == null
                    ? const CircularProgressIndicator()
                    : Text(error!))
            : ListView(padding: const EdgeInsets.all(16), children: [
                PredictionCard(question: question, onTap: () {}),
                Consumer(builder: (_, ref, __) {
                  final candles = ref.watch(liveCandlesProvider((
                    assetId: question['instrumentId'] as String,
                    interval: interval,
                    limit: 150
                  )));
                  return Column(children: [
                    Wrap(spacing: 8, children: [
                      for (final value in ['1m', '5m', '15m', '1h', '1d'])
                        ChoiceChip(
                            label: Text(value),
                            selected: interval == value,
                            onSelected: (_) => setState(() => interval = value))
                    ]),
                    SizedBox(
                        height: 300,
                        child: candles.when(
                            data: (series) => series.candles.isEmpty
                                ? const Center(
                                    child: Text('No market bars available'))
                                : LiveTradeChart(
                                    series: series,
                                    precision:
                                        question['pricePrecision'] as int,
                                    markers: [
                                        ChartTradeMarker(
                                            id: 'target',
                                            openedAt: DateTime.parse(
                                                question['referenceTimestamp']
                                                    as String),
                                            price: predictionNumber(
                                                question['targetPrice']),
                                            label: 'Target',
                                            color: const Color(0xFFF6C342))
                                      ]),
                            error: (_, __) => const Center(
                                child: Text(
                                    'Price chart unavailable. Retry shortly.')),
                            loading: () => const Center(
                                child: CircularProgressIndicator())))
                  ]);
                }),
                const SizedBox(height: 16),
                const Text('Settlement rules',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text(
                    '${question['condition']} is strict; equality settles NO. Source: ${question['referenceSource']}. Uses the last archived one-second close before UTC expiry. Local expiry: ${DateTime.parse(question['expiresAt'] as String).toLocal()}. UTC: ${question['expiresAt']}. No winning stakes: everyone is refunded. Missing verified price: awaiting result, then refunded after 24 hours.'),
                if (question['settlementPrice'] != null)
                  const SizedBox(height: 8),
                if (question['generationContext'] != null)
                  Text(
                      '${predictionObject(question['generationContext'])['explanation']} Historical anchor: ${predictionObject(question['generationContext'])['anchorPrice']} at ${predictionObject(question['generationContext'])['anchorTimestamp']}.'),
                if (ownPositions.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Your positions',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  for (final p in ownPositions)
                    Text(
                        "${p['side']} · ${predictionMoney(p['stake'])} · ${p['result']}${p['payoutAmount'] == null ? '' : ' · Returned ${predictionMoney(p['payoutAmount'])}'}"),
                  const SizedBox(height: 12),
                ],
                if (question['settlementPrice'] != null)
                  Text(
                      'Verified result: ${question['settlementPrice']} · ${question['settlementSource']} · ${question['settlementTimestamp']}'),
                if (question['cancellationReason'] != null)
                  Text('Refund reason: ${question['cancellationReason']}'),
                if (question['status'] == 'OPEN' &&
                    DateTime.parse(question['expiresAt'] as String)
                        .isAfter(DateTime.now())) ...[
                  const SizedBox(height: 20),
                  const Text('Participate · Demo USD only',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  if (authenticated)
                    ref.watch(accountsProvider).when(
                        data: (accounts) => Text(
                            'Demo available: ${predictionMoney(accounts.where((a) => a.mode.apiValue == 'DEMO').firstOrNull?.wallets.firstOrNull?.available)}'),
                        error: (_, __) => const Text('Balance unavailable'),
                        loading: () => const LinearProgressIndicator()),
                  SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'YES', label: Text('YES')),
                        ButtonSegment(value: 'NO', label: Text('NO'))
                      ],
                      selected: {
                        side
                      },
                      onSelectionChanged: (values) =>
                          setState(() => side = values.first)),
                  const SizedBox(height: 12),
                  TextField(
                      controller: stake,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                          labelText: 'Demo USD stake', prefixText: '\$ '),
                      onChanged: (_) => setState(() {})),
                  Builder(builder: (_) {
                    final amount = double.tryParse(stake.text) ?? 0,
                        yes = predictionNumber(question['yesDemoPool']),
                        no = predictionNumber(question['noDemoPool']);
                    final own = side == 'YES' ? yes : no, total = yes + no;
                    final estimate = amount <= 0
                        ? 0
                        : amount * (total + amount) / (own + amount);
                    return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                            'Illustrative return if correct: ${predictionMoney(estimate)} (includes stake). If incorrect: \$0.00. Zero fee. Final allocation is rounded to cents.'));
                  }),
                  FilledButton(
                      onPressed: busy ? null : _place,
                      child: Text(busy
                          ? 'Submitting…'
                          : authenticated
                              ? 'Place $side prediction'
                              : 'Sign in to participate')),
                ],
                if (authenticated)
                  TextButton.icon(
                      onPressed: () async {
                        final reason = TextEditingController();
                        final value = await showDialog<String>(
                            context: context,
                            builder: (_) => AlertDialog(
                                    title: const Text('Report prediction'),
                                    content: TextField(
                                        controller: reason,
                                        maxLength: 500,
                                        decoration: const InputDecoration(
                                            labelText: 'Reason')),
                                    actions: [
                                      TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context),
                                          child: const Text('Cancel')),
                                      FilledButton(
                                          onPressed: () {
                                            if (reason.text.trim().isNotEmpty) {
                                              Navigator.pop(
                                                  context, reason.text.trim());
                                            }
                                          },
                                          child: const Text('Report'))
                                    ]));
                        reason.dispose();
                        if (value == null) return;
                        try {
                          await ref
                              .read(predictionRepositoryProvider)
                              .report(widget.id, value);
                          showTopNotification('Report submitted.',
                              success: true);
                        } catch (e) {
                          showTopNotification('$e');
                        }
                      },
                      icon: const Icon(Icons.flag_outlined),
                      label: const Text('Report this prediction')),
              ]));
  }
}

class CreatePredictionScreen extends ConsumerStatefulWidget {
  const CreatePredictionScreen({super.key});
  @override
  ConsumerState<CreatePredictionScreen> createState() =>
      _CreatePredictionState();
}

class _CreatePredictionState extends ConsumerState<CreatePredictionScreen> {
  String asset = 'btc-usd', condition = 'ABOVE';
  int minutes = 60;
  DateTime? customExpiry;
  final target = TextEditingController();
  bool busy = false;
  @override
  void dispose() {
    target.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    final price = double.tryParse(target.text);
    if (price == null || !price.isFinite || price <= 0) {
      showTopNotification('Enter a positive target price.');
      return;
    }
    final expiry =
        customExpiry ?? DateTime.now().add(Duration(minutes: minutes));
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
                title: const Text('Publish prediction?'),
                content: Text(
                    'Will $asset be ${condition.toLowerCase()} \$${target.text} at ${expiry.toLocal()}?\n\nTerms cannot be edited after publication. Equality settles NO. Demo USD only.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Back')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Publish'))
                ]));
    if (confirmed != true || !mounted) return;
    setState(() => busy = true);
    try {
      await ref.read(predictionRepositoryProvider).submit('questions', {
        'instrumentId': asset,
        'condition': condition,
        'targetPrice': target.text.trim(),
        'expiresAt': expiry.toUtc().toIso8601String()
      });
      showTopNotification('Prediction published.', success: true);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      showTopNotification('$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Create prediction')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const Text('Turn insight into a clear question',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        const Text(
            'Choose a crypto market, target and expiry. Up to five open predictions. Targets must be within 50% of the verified current price.'),
        const SizedBox(height: 20),
        ref.watch(assetsProvider).when(
            data: (assets) => DropdownButtonFormField<String>(
                initialValue: asset,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Crypto market'),
                items: assets
                    .where((a) => a.assetClass.toUpperCase() == 'CRYPTO')
                    .map((a) => DropdownMenuItem(
                        value: a.id, child: Text('${a.symbol} · ${a.name}')))
                    .toList(),
                onChanged: (v) => setState(() => asset = v!)),
            error: (_, __) =>
                const Text('Markets unavailable. Retry when connected.'),
            loading: () => const LinearProgressIndicator()),
        const SizedBox(height: 16),
        SegmentedButton<String>(segments: const [
          ButtonSegment(value: 'ABOVE', label: Text('Above')),
          ButtonSegment(value: 'BELOW', label: Text('Below'))
        ], selected: {
          condition
        }, onSelectionChanged: (v) => setState(() => condition = v.first)),
        const SizedBox(height: 16),
        TextField(
            controller: target,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
                labelText: 'Target price (USD)', prefixText: '\$ ')),
        const SizedBox(height: 16),
        DropdownButtonFormField<int>(
            initialValue: minutes,
            decoration: const InputDecoration(labelText: 'Expiry from now'),
            items: const [
              DropdownMenuItem(value: 15, child: Text('15 minutes')),
              DropdownMenuItem(value: 60, child: Text('1 hour')),
              DropdownMenuItem(value: 240, child: Text('4 hours')),
              DropdownMenuItem(value: 1440, child: Text('1 day')),
              DropdownMenuItem(value: 10080, child: Text('1 week'))
            ],
            onChanged: (v) => setState(() {
                  minutes = v!;
                  customExpiry = null;
                })),
        TextButton.icon(
            onPressed: () async {
              final now = DateTime.now();
              final date = await showDatePicker(
                  context: context,
                  initialDate: now.add(const Duration(days: 1)),
                  firstDate: now,
                  lastDate: now.add(const Duration(days: 30)));
              if (date == null || !context.mounted) return;
              final time = await showTimePicker(
                  context: context, initialTime: TimeOfDay.now());
              if (time != null) {
                setState(() => customExpiry = DateTime(
                    date.year, date.month, date.day, time.hour, time.minute));
              }
            },
            icon: const Icon(Icons.schedule),
            label: Text(customExpiry == null
                ? 'Choose custom date and time (10 min–30 days)'
                : 'Expiry: ${customExpiry!.toLocal()}')),
        const SizedBox(height: 24),
        FilledButton(
            onPressed: busy ? null : _publish,
            child: Text(busy ? 'Publishing…' : 'Preview & publish')),
      ]));
}
