import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:primevest_mobile/app/top_notification.dart';
import 'package:primevest_mobile/core/api/api_contract.dart';
import 'package:primevest_mobile/core/app_providers.dart';
import 'package:primevest_mobile/core/auth/verification_repository.dart';

class TwoFactorPrompt extends ConsumerWidget {
  const TwoFactorPrompt({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(verificationStatusProvider).valueOrNull;
    if (status == null || status.enabled) return const SizedBox.shrink();
    return Material(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: .12),
      child: SafeArea(
          bottom: false,
          top: false,
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.shield_outlined, size: 22),
            title: const Text(
                'Protect your account with two-factor authentication',
                style: TextStyle(fontSize: 12)),
            trailing: TextButton(
                onPressed: () => context.push('/security'),
                child: const Text('Set up')),
            onTap: () => context.push('/security'),
          )),
    );
  }
}

class TwoFactorSettings extends ConsumerWidget {
  const TwoFactorSettings({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(verificationStatusProvider).when(
            loading: () => const LinearProgressIndicator(),
            error: (error, _) => ListTile(
                title: const Text('Could not load two-factor settings'),
                trailing: IconButton(
                    onPressed: () => ref.invalidate(verificationStatusProvider),
                    icon: const Icon(Icons.refresh))),
            data: (status) {
              if (status == null) return const SizedBox.shrink();
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Two-factor authentication',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(status.enabled
                        ? 'Withdrawals require a code from an enabled method. You can enable both methods and choose one when withdrawing.'
                        : 'Add an extra layer of protection. Enable email OTP, an authenticator, or both before withdrawing.'),
                    Card(
                        child: ListTile(
                      leading: const Icon(Icons.email_outlined),
                      title: const Text('Email OTP'),
                      subtitle: Text(status.emailEnabled
                          ? 'Enabled • ${status.email ?? ""}'
                          : status.emailAvailable
                              ? status.email ?? 'Your account email'
                              : 'Email delivery is not configured yet'),
                      trailing: status.emailEnabled
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : TextButton(
                              onPressed: status.emailAvailable
                                  ? () => _enroll(context, ref, false)
                                  : null,
                              child: const Text('Enable')),
                    )),
                    Card(
                        child: ListTile(
                      leading: const Icon(Icons.phonelink_lock),
                      title: const Text('Authenticator app'),
                      subtitle: Text(status.authenticatorEnabled
                          ? 'Enabled • 6-digit time-based codes'
                          : 'Google Authenticator, Microsoft Authenticator or similar'),
                      trailing: status.authenticatorEnabled
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : TextButton(
                              onPressed: status.authenticatorAvailable
                                  ? () => _enroll(context, ref, true)
                                  : null,
                              child: const Text('Enable')),
                    )),
                    const SizedBox(height: 18),
                  ]);
            },
          );
  Future<void> _enroll(
      BuildContext context, WidgetRef ref, bool authenticator) async {
    await showDialog<bool>(
        context: context,
        builder: (_) => FactorEnrollmentDialog(authenticator: authenticator));
    ref.invalidate(verificationStatusProvider);
  }
}

class FactorEnrollmentDialog extends ConsumerStatefulWidget {
  const FactorEnrollmentDialog({super.key, required this.authenticator});
  final bool authenticator;
  @override
  ConsumerState<FactorEnrollmentDialog> createState() =>
      _FactorEnrollmentDialogState();
}

class _FactorEnrollmentDialogState
    extends ConsumerState<FactorEnrollmentDialog> {
  final code = TextEditingController();
  JsonObject? setup;
  String? error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await ref.read(verificationRepositoryProvider).command(
          widget.authenticator ? 'authenticator/setup' : 'email/setup');
      if (mounted) setState(() => setup = result);
    } catch (e) {
      if (mounted) setState(() => error = _message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _confirm() async {
    if (!RegExp(r'^\d{6}$').hasMatch(code.text)) {
      setState(() => error = 'Enter the 6-digit code.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref.read(verificationRepositoryProvider).command(
          widget.authenticator ? 'authenticator/confirm' : 'email/confirm',
          code.text);
      ref.invalidate(verificationStatusProvider);
      if (mounted) Navigator.pop(context, true);
      showTopNotification('Two-factor authentication enabled.');
    } catch (e) {
      if (mounted) setState(() => error = _message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(
            widget.authenticator ? 'Set up authenticator' : 'Enable email OTP'),
        content: SizedBox(
            width: 320,
            child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (busy) const LinearProgressIndicator(),
              if (setup != null) ...[
                if (widget.authenticator) ...[
                  const Text(
                      'Scan with your authenticator app, or enter the setup key manually. Keep this key private.'),
                  const SizedBox(height: 12),
                  Container(
                      color: Colors.white,
                      child: QrImageView(
                          data: setup!['otpAuthUrl'] as String, size: 200)),
                  SelectableText(setup!['secret'] as String,
                      textAlign: TextAlign.center),
                  TextButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(
                            ClipboardData(text: setup!['secret'] as String));
                        showTopNotification(
                            'Setup key copied. Keep it private.');
                      },
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy setup key')),
                ] else
                  const Text(
                      'Enter the code sent to your account email. It expires in 5 minutes.'),
                TextField(
                    controller: code,
                    enabled: !busy,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6)
                    ],
                    decoration: const InputDecoration(
                        labelText: '6-digit verification code')),
              ],
              if (error != null)
                Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error))),
            ]))),
        actions: [
          TextButton(
              onPressed: busy ? null : () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: busy
                  ? null
                  : setup == null
                      ? _start
                      : _confirm,
              child: Text(setup == null ? 'Retry' : 'Enable')),
        ],
      );
}

typedef WithdrawalFactor = ({String method, String code});
Future<WithdrawalFactor?> requestWithdrawalFactor(
        BuildContext context, VerificationStatus status) =>
    showDialog<WithdrawalFactor>(
        context: context,
        builder: (_) => WithdrawalFactorDialog(status: status));

class WithdrawalFactorDialog extends ConsumerStatefulWidget {
  const WithdrawalFactorDialog({super.key, required this.status});
  final VerificationStatus status;
  @override
  ConsumerState<WithdrawalFactorDialog> createState() =>
      _WithdrawalFactorDialogState();
}

class _WithdrawalFactorDialogState
    extends ConsumerState<WithdrawalFactorDialog> {
  final code = TextEditingController();
  late String method =
      widget.status.authenticatorEnabled ? 'AUTHENTICATOR' : 'EMAIL';
  bool sending = false;
  bool sent = false;
  DateTime? sentAt;
  String? error;
  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (sentAt != null && DateTime.now().difference(sentAt!).inSeconds < 60) {
      setState(() => error = 'Wait one minute before requesting another code.');
      return;
    }
    setState(() {
      sending = true;
      error = null;
    });
    try {
      await ref.read(verificationRepositoryProvider).command('email-code');
      if (mounted) {
        setState(() {
          sent = true;
          sentAt = DateTime.now();
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = _message(e));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Verify withdrawal'),
        content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
              'Use your Zettax verification code, never your mobile-wallet PIN or OTP.'),
          if (widget.status.authenticatorEnabled && widget.status.emailEnabled)
            DropdownButton<String>(
                value: method,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(
                      value: 'AUTHENTICATOR', child: Text('Authenticator')),
                  DropdownMenuItem(value: 'EMAIL', child: Text('Email OTP'))
                ],
                onChanged: sending
                    ? null
                    : (value) => setState(() {
                          method = value!;
                          code.clear();
                          error = null;
                        })),
          if (method == 'EMAIL') ...[
            Text(sent
                ? 'Code sent to ${widget.status.email}. Valid for 5 minutes.'
                : 'Send a code to ${widget.status.email}.'),
            TextButton(
                onPressed:
                    sending || !widget.status.emailAvailable ? null : _send,
                child: Text(sending
                    ? 'Sending…'
                    : sent
                        ? 'Resend code'
                        : 'Send code')),
          ] else
            const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                    'Enter the current code from your authenticator app. Each code can be used once.')),
          TextField(
              controller: code,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6)
              ],
              decoration: const InputDecoration(
                  labelText: '6-digit verification code')),
          if (error != null)
            Text(error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ])),
        actions: [
          TextButton(
              onPressed: sending ? null : () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: sending
                  ? null
                  : () {
                      if (!RegExp(r'^\d{6}$').hasMatch(code.text) ||
                          (method == 'EMAIL' && !sent)) {
                        setState(() =>
                            error = 'Send and enter a valid 6-digit code.');
                        return;
                      }
                      Navigator.pop(context, (method: method, code: code.text));
                    },
              child: const Text('Submit withdrawal'))
        ],
      );
}

String _message(Object error) => error is ApiFailure
    ? error.message
    : 'Could not complete verification. Please retry.';
