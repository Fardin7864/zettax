import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:primevest_mobile/app/design_system.dart';
import 'package:primevest_mobile/app/top_notification.dart';
import 'package:primevest_mobile/core/api/api_contract.dart';
import 'package:primevest_mobile/core/app_providers.dart';
import 'package:primevest_mobile/core/funding/funding_models.dart';
import 'package:primevest_mobile/features/funding/funding_brand.dart';

Future<void> _recoverFunding(BuildContext context, WidgetRef ref) async {
  final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
              title: const Text('Resolve previous request'),
              content: const Text(
                  'Retry your original funding request? The same request key will be used so it cannot create a second deposit or withdrawal.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Not now')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Retry original'))
              ]));
  if (agreed != true) return;
  try {
    await ref.read(fundingRepositoryProvider).retryPending();
    ref.invalidate(accountsProvider);
    if (context.mounted) {
      showTopNotification('Request resolved. Check funding history.');
    }
  } catch (error) {
    if (context.mounted) {
      showTopNotification(_message(error), success: false);
    }
  }
}

class FundingHistoryScreen extends ConsumerStatefulWidget {
  const FundingHistoryScreen(
      {super.key, required this.path, this.embedded = false});
  final String path;
  final bool embedded;
  @override
  ConsumerState<FundingHistoryScreen> createState() => _FundingHistoryState();
}

class _FundingHistoryState extends ConsumerState<FundingHistoryScreen> {
  late Future<List<JsonObject>> history;
  ProviderSubscription<int>? realtimeSubscription;
  TabController? tabController;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller =
        widget.embedded ? DefaultTabController.maybeOf(context) : null;
    if (controller == tabController) return;
    tabController?.removeListener(_tabChanged);
    tabController = controller;
    tabController?.addListener(_tabChanged);
  }

  void _tabChanged() {
    if (tabController?.index == 1 && tabController?.indexIsChanging == false) {
      _reload();
    }
  }

  @override
  void initState() {
    super.initState();
    history = ref.read(fundingRepositoryProvider).history(widget.path);
    realtimeSubscription = ref.listenManual<int>(
      fundingRealtimeRevisionProvider,
      (_, __) => _reload(),
    );
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      history = ref.read(fundingRepositoryProvider).history(widget.path);
    });
  }

  @override
  void dispose() {
    realtimeSubscription?.close();
    tabController?.removeListener(_tabChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(
              title: Text(widget.path == '/deposits'
                  ? 'Deposit history'
                  : 'Withdrawal history'),
              actions: [
                  IconButton(
                      onPressed: _reload, icon: const Icon(Icons.refresh))
                ]),
      body: FutureBuilder<List<JsonObject>>(
          future: history,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text(_message(snapshot.error!)));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final rows = snapshot.data!;
            if (rows.isEmpty) {
              return const Center(child: Text('No requests yet.'));
            }
            return ListView.builder(
                itemCount: rows.length,
                itemBuilder: (context, index) {
                  final row = rows[index];
                  final status = row['status']?.toString() ?? '';
                  final pending = status == 'PENDING_REVIEW' ||
                      status == 'REQUESTED' ||
                      status == 'UNDER_REVIEW' ||
                      status == 'APPROVED' ||
                      status == 'PROCESSING';
                  return ListTile(
                      leading: FundingBrandLogo(
                          type: (row['paymentMethod'] as Map?)?['type']
                              as String?,
                          width: 46,
                          height: 34),
                      tileColor: pending
                          ? PrimeVestDesignSystem.primaryGold
                              .withValues(alpha: 0.12)
                          : null,
                      title: Text('${row['usdAmount'] == null ? '' : '\$${row['usdAmount']} · '}৳${row['amount']} · ${row['status']}'),
                      subtitle: Text(
                          '${row['providerTransactionId'] ?? row['receiverMobile'] ?? ''}\n${row['rejectionReason'] ?? 'Updated: ${row['updatedAt'] ?? row['createdAt']}'}'),
                      isThreeLine: true);
                });
          }));
}

class CashInScreen extends ConsumerStatefulWidget {
  const CashInScreen({super.key});

  @override
  ConsumerState<CashInScreen> createState() => _CashInScreenState();
}

class _CashInScreenState extends ConsumerState<CashInScreen> {
  final amount = TextEditingController();
  final sender = TextEditingController();
  final transactionId = TextEditingController();
  String? selectedId;
  XFile? screenshot;
  bool submitting = false;

  @override
  void dispose() {
    amount.dispose();
    sender.dispose();
    transactionId.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
            title: const Text('Deposit'),
            bottom: const TabBar(
                tabs: [Tab(text: 'Request'), Tab(text: 'History')])),
        body: TabBarView(children: [
          ref.watch(depositMethodsProvider).when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => _LoadFailure(
                  message: _message(error),
                  retry: () => ref.invalidate(depositMethodsProvider),
                ),
                data: (data) => _body(data),
              ),
          const FundingHistoryScreen(path: '/deposits', embedded: true)
        ]),
      ));

  Widget _body(FundingMethods data) {
    final methods = data.methods;
    if (methods.isEmpty) {
      return const _LoadFailure(message: 'No deposit methods are configured.');
    }
    selectedId ??= methods.first.id;
    final selected = methods.firstWhere(
      (item) => item.id == selectedId,
      orElse: () => methods.first,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        if (!data.submissionsEnabled)
          _StatusBanner(
            enabled: data.submissionsEnabled,
            enabledText: data.virtualFunding
                ? 'Virtual funding is active. Submit the amount and reference for admin review; no real money is transferred.'
                : 'Send Money only to the selected number. Your balance changes only after manual verification.',
            disabledText:
                'Deposits are not accepting transfers yet. Do not send money until this screen shows Active.',
          ),
        const SizedBox(height: 20),
        const _Title('1. Choose payment service'),
        const SizedBox(height: 10),
        _MethodSelector(
          methods: methods,
          selectedId: selected.id,
          onSelected: (id) => setState(() => selectedId = id),
        ),
        const SizedBox(height: 16),
        _ReceivingCard(method: selected, reveal: data.submissionsEnabled),
        const SizedBox(height: 22),
        const _Title('2. Enter transfer details'),
        Text('Deposit rate: ৳${data.depositBdtPerUsd} = \$1.00. The approved BDT amount is converted to USD in your wallet.',
            style: const TextStyle(color: PrimeVestDesignSystem.textMuted)),
        const SizedBox(height: 10),
        TextField(
          controller: amount,
          enabled: data.submissionsEnabled,
          onChanged: (_) => setState(() {}),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Amount (BDT)',
            prefixText: '৳ ',
            helperText: data.virtualFunding
                ? 'Minimum: ৳${selected.minimum} • no platform maximum'
                : 'Allowed: ৳${selected.minimum} – ৳${selected.maximum}',
          ),
        ),
        if ((double.tryParse(amount.text) ?? 0) > 0)
          Text('Estimated USD credit after approval: \$${((double.tryParse(amount.text) ?? 0) / (double.tryParse(data.depositBdtPerUsd) ?? 125)).toStringAsFixed(2)}'),
        const SizedBox(height: 12),
        TextField(
          controller: sender,
          enabled: data.submissionsEnabled,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Your sending number',
            hintText: '01XXXXXXXXX',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: transactionId,
          enabled: data.submissionsEnabled,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Transaction ID',
            hintText: 'Enter exactly as shown in the receipt',
          ),
        ),
        const SizedBox(height: 12),
        ...[
          OutlinedButton.icon(
            onPressed: data.submissionsEnabled ? _pickScreenshot : null,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: Text(screenshot == null
                ? 'Attach screenshot (optional)'
                : screenshot!.name),
          ),
          const SizedBox(height: 16),
          const Text(
              'Screenshots are stored securely and deleted after 7 days.'),
          const SizedBox(height: 12),
        ],
        FilledButton.icon(
          onPressed:
              data.submissionsEnabled && !submitting ? _submitCashIn : null,
          icon: const Icon(Icons.upload_file),
          label: Text(submitting
              ? 'Uploading and submitting…'
              : 'Submit for verification'),
        ),
        const SizedBox(height: 10),
        Text(
          data.virtualFunding
              ? 'This account uses virtual funds only. No bKash, Nagad, or Rocket money will be moved.'
              : 'Never share a PIN or OTP. A screenshot and transaction ID are evidence only; an operator must verify the payment independently.',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: PrimeVestDesignSystem.textMuted,
            fontSize: 11,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Future<void> _pickScreenshot() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1800,
    );
    if (file != null && mounted) setState(() => screenshot = file);
  }

  Future<void> _submitCashIn() async {
    final repository = ref.read(fundingRepositoryProvider);
    if (await repository.pending() != null) {
      if (!mounted) return;
      await _recoverFunding(context, ref);
      return;
    }
    if (amount.text.trim().isEmpty ||
        sender.text.trim().isEmpty ||
        transactionId.text.trim().isEmpty) {
      _notice('Enter the amount, sender number, and transaction ID.');
      return;
    }
    setState(() => submitting = true);
    final submittedAmount = amount.text.trim();
    final submittedSender = sender.text.trim();
    final submittedTransaction = transactionId.text.trim();
    final submittedMethod = selectedId!;
    try {
      final key = screenshot == null
          ? null
          : await repository.uploadEvidence(
              await screenshot!.readAsBytes(), screenshot!.name);
      await repository.createDeposit(
          methodId: submittedMethod,
          amount: submittedAmount,
          expectedConversionRate: ref.read(depositMethodsProvider).valueOrNull?.depositBdtPerUsd,
          senderMobile: submittedSender,
          transactionId: submittedTransaction,
          evidenceObjectKey: key);
      if (mounted) {
        amount.clear();
        sender.clear();
        transactionId.clear();
        setState(() => screenshot = null);
        ref.read(fundingRealtimeRevisionProvider.notifier).state++;
        _notice(
            'Deposit submitted. Your claim is awaiting independent transfer verification and approval.');
      }
    } catch (error) {
      if (mounted) {
        ref.invalidate(depositMethodsProvider);
        _notice(_message(error));
      }
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  void _notice(String message) {
    showTopNotification(message);
  }
}

class WithdrawScreen extends ConsumerStatefulWidget {
  const WithdrawScreen({super.key});

  @override
  ConsumerState<WithdrawScreen> createState() => _WithdrawScreenState();
}

class _WithdrawScreenState extends ConsumerState<WithdrawScreen> {
  final amount = TextEditingController();
  final receiver = TextEditingController();
  String? selectedId;
  bool submitting = false;

  @override
  void dispose() {
    amount.dispose();
    receiver.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
            title: const Text('Withdraw'),
            bottom: const TabBar(
                tabs: [Tab(text: 'Request'), Tab(text: 'History')])),
        body: TabBarView(children: [
          ref.watch(withdrawalMethodsProvider).when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => _LoadFailure(
                  message: _message(error),
                  retry: () => ref.invalidate(withdrawalMethodsProvider),
                ),
                data: (data) => _body(data),
              ),
          const FundingHistoryScreen(path: '/withdrawals', embedded: true)
        ]),
      ));

  Widget _body(FundingMethods data) {
    if (data.methods.isEmpty) {
      return const _LoadFailure(
          message: 'No withdrawal methods are configured.');
    }
    selectedId ??= data.methods.first.id;
    final enabled = data.submissionsEnabled && !submitting;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        const _FundingWalletBalances(),
        const SizedBox(height: 16),
        if (!data.submissionsEnabled)
          _StatusBanner(
            enabled: data.submissionsEnabled,
            enabledText: data.virtualFunding
                ? 'Your requested amount is immediately deducted from available balance and locked until review. No real payment is sent.'
                : 'Withdrawals are reviewed manually. Funds are locked when your request is accepted by the server.',
            disabledText:
                'Withdrawals are not accepting requests yet. Your REAL balance remains unchanged.',
          ),
        const SizedBox(height: 20),
        const _Title('Choose receiving service'),
        const SizedBox(height: 10),
        _MethodSelector(
          methods: data.methods,
          selectedId: selectedId!,
          onSelected: enabled ? (id) => setState(() => selectedId = id) : null,
        ),
        const SizedBox(height: 18),
        Text('Withdrawal rate: \$1.00 = ৳${data.withdrawalBdtPerUsd}. Your USD balance is locked now; the BDT payout is fixed when you submit.',
            style: const TextStyle(color: PrimeVestDesignSystem.textMuted)),
        if ((double.tryParse(amount.text) ?? 0) > 0)
          Text('Estimated payout: ৳${((double.tryParse(amount.text) ?? 0) * (double.tryParse(data.withdrawalBdtPerUsd) ?? 118)).toStringAsFixed(2)}'),
        const SizedBox(height: 10),
        TextField(
          controller: amount,
          enabled: enabled,
          onChanged: (_) => setState(() {}),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Withdrawal amount (USD)',
            prefixText: '\$ ',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: receiver,
          enabled: enabled,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Your receiving number',
            hintText: '01XXXXXXXXX',
          ),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: enabled ? _submit : null,
          icon: submitting
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.account_balance_wallet_outlined),
          label: const Text('Request withdrawal'),
        ),
        const SizedBox(height: 12),
        Text(
          data.virtualFunding
              ? 'This withdraws virtual balance only; it does not send real money.'
              : 'Approved identity verification is required. Zettax will never ask for the PIN or OTP of your bKash, Nagad, or Rocket account.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: PrimeVestDesignSystem.textMuted,
            fontSize: 11,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (await ref.read(fundingRepositoryProvider).pending() != null) {
      if (!mounted) return;
      await _recoverFunding(context, ref);
      return;
    }
    if (amount.text.trim().isEmpty || receiver.text.trim().isEmpty) {
      _notice('Enter the amount and receiving number.');
      return;
    }
    setState(() => submitting = true);
    try {
      await ref.read(fundingRepositoryProvider).createWithdrawal(
            methodId: selectedId!,
            amount: amount.text.trim(),
            expectedConversionRate: ref.read(withdrawalMethodsProvider).valueOrNull?.withdrawalBdtPerUsd,
            receiverMobile: receiver.text.trim(),
          );
      if (mounted) {
        _notice(
            'Withdrawal submitted. The amount is locked and no longer available to trade or withdraw.');
        amount.clear();
        receiver.clear();
        ref.invalidate(accountsProvider);
        ref.read(fundingRealtimeRevisionProvider.notifier).state++;
      }
    } catch (error) {
      if (mounted) {
        ref.invalidate(withdrawalMethodsProvider);
        _notice(_message(error));
      }
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  void _notice(String message) {
    showTopNotification(message);
  }
}

class _FundingWalletBalances extends ConsumerWidget {
  const _FundingWalletBalances();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(accountsProvider).when(
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => const Text('Balance unavailable. Please retry.'),
          data: (accounts) {
            final wallet = accounts
                .where((account) => account.mode.apiValue == 'REAL')
                .firstOrNull
                ?.wallets
                .firstOrNull;
            return Card(
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      Expanded(
                          child:
                              Text('Available\n\$${wallet?.available ?? '—'}')),
                      Expanded(
                          child: Text('Locked\n\$${wallet?.locked ?? '—'}')),
                    ])));
          },
        );
  }
}

class _MethodSelector extends StatelessWidget {
  const _MethodSelector({
    required this.methods,
    required this.selectedId,
    required this.onSelected,
  });
  final List<FundingMethod> methods;
  final String selectedId;
  final ValueChanged<String>? onSelected;

  @override
  Widget build(BuildContext context) => Row(
        children: methods.map((method) {
          final brand = FundingBrand.forType(method.type);
          final color = brand?.color ?? PrimeVestDesignSystem.primaryGold;
          final selected = method.id == selectedId;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InkWell(
                onTap: onSelected == null ? null : () => onSelected!(method.id),
                borderRadius: BorderRadius.circular(14),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 82,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: selected ? .22 : .08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: color.withValues(alpha: selected ? 1 : .35),
                        width: selected ? 2 : 1),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FundingBrandLogo(
                          type: method.type, width: 52, height: 34),
                      const SizedBox(height: 5),
                      Text(method.displayName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      );
}

class _ReceivingCard extends StatelessWidget {
  const _ReceivingCard({required this.method, required this.reveal});
  final FundingMethod method;
  final bool reveal;

  @override
  Widget build(BuildContext context) {
    final color = FundingBrand.forType(method.type)?.color ??
        PrimeVestDesignSystem.primaryGold;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: PrimeVestDesignSystem.surfaceDark,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: .55)),
      ),
      child: reveal
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                FundingBrandLogo(type: method.type, width: 56, height: 38),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(
                  '${method.displayName} • ${_titleCase(method.accountType)}',
                  style: TextStyle(color: color, fontWeight: FontWeight.w800),
                )),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: Text(method.accountNumber,
                      style: const TextStyle(
                          fontSize: 25, fontWeight: FontWeight.w900)),
                ),
                IconButton.filledTonal(
                  tooltip: 'Copy number',
                  onPressed: () {
                    Clipboard.setData(
                        ClipboardData(text: method.accountNumber));
                    showTopNotification('Number copied');
                  },
                  icon: const Icon(Icons.copy),
                ),
              ]),
              const SizedBox(height: 8),
              Text(method.instructions,
                  style: const TextStyle(
                      color: PrimeVestDesignSystem.textMuted, height: 1.4)),
            ])
          : const Row(children: [
              Icon(Icons.visibility_off_outlined,
                  color: PrimeVestDesignSystem.textMuted),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'The receiving number is hidden until Deposit is activated.',
                  style: TextStyle(color: PrimeVestDesignSystem.textMuted),
                ),
              ),
            ]),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.enabled,
    required this.enabledText,
    required this.disabledText,
  });
  final bool enabled;
  final String enabledText;
  final String disabledText;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: (enabled
                  ? PrimeVestDesignSystem.positive
                  : PrimeVestDesignSystem.primaryGold)
              .withValues(alpha: .1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: (enabled
                    ? PrimeVestDesignSystem.positive
                    : PrimeVestDesignSystem.primaryGold)
                .withValues(alpha: .45),
          ),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(enabled ? Icons.verified_outlined : Icons.info_outline,
              color: enabled
                  ? PrimeVestDesignSystem.positive
                  : PrimeVestDesignSystem.primaryGold),
          const SizedBox(width: 10),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(enabled ? 'Active' : 'Not accepting requests',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(enabled ? enabledText : disabledText,
                  style: const TextStyle(
                      color: PrimeVestDesignSystem.textMuted, height: 1.35)),
            ]),
          ),
        ]),
      );
}

class _Title extends StatelessWidget {
  const _Title(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800));
}

class _LoadFailure extends StatelessWidget {
  const _LoadFailure({required this.message, this.retry});
  final String message;
  final VoidCallback? retry;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.account_balance_wallet_outlined, size: 42),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (retry != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(onPressed: retry, child: const Text('Retry')),
            ],
          ]),
        ),
      );
}

String _message(Object error) => error is ApiFailure
    ? error.message
    : 'Could not reach the funding service.';

String _titleCase(String value) =>
    value.isEmpty ? value : '${value[0]}${value.substring(1).toLowerCase()}';
