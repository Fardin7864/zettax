import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:primevest_mobile/app/top_notification.dart';
import 'package:primevest_mobile/core/api/api_contract.dart';
import 'package:primevest_mobile/core/app_providers.dart';

class SecurityScreen extends ConsumerStatefulWidget {
  const SecurityScreen({super.key});

  @override
  ConsumerState<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends ConsumerState<SecurityScreen> {
  late Future<List<JsonObject>> sessions;
  late Future<JsonObject> verification;
  final authenticatorCode = TextEditingController();
  String? pendingSecret;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    sessions = ref.read(sessionProvider).phase == SessionPhase.authenticated
        ? ref.read(authRepositoryProvider).sessions()
        : Future.value(const []);
    verification = ref.read(sessionProvider).phase == SessionPhase.authenticated
        ? ref.read(authRepositoryProvider).verificationStatus()
        : Future.value({});
  }

  void refresh() => setState(() {
        sessions = ref.read(authRepositoryProvider).sessions();
        verification = ref.read(authRepositoryProvider).verificationStatus();
      });

  @override
  void dispose() {
    authenticatorCode.dispose();
    super.dispose();
  }

  Future<void> beginAuthenticator() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final result =
          await ref.read(authRepositoryProvider).beginAuthenticator();
      if (mounted) setState(() => pendingSecret = result['secret']?.toString());
    } on ApiFailure catch (error) {
      showTopNotification(error.message, success: false);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> confirmAuthenticator() async {
    if (busy || !RegExp(r'^\d{6}$').hasMatch(authenticatorCode.text.trim())) {
      showTopNotification(
          'Enter the six-digit code from your authenticator app.',
          success: false);
      return;
    }
    setState(() => busy = true);
    try {
      await ref
          .read(authRepositoryProvider)
          .confirmAuthenticator(authenticatorCode.text.trim());
      if (mounted) {
        setState(() => pendingSecret = null);
        authenticatorCode.clear();
        verification = ref.read(authRepositoryProvider).verificationStatus();
        showTopNotification('Authenticator verification is enabled.');
      }
    } on ApiFailure catch (error) {
      showTopNotification(error.message, success: false);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> revoke(String id) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await ref.read(authRepositoryProvider).revokeSession(id);
      if (mounted) {
        showTopNotification('Device session revoked.');
        refresh();
      }
    } on ApiFailure catch (error) {
      showTopNotification(error.message, success: false);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> signOutAll() async {
    if (busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out all devices?'),
        content: const Text(
            'Every active session, including this phone, will be signed out.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Sign out all')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => busy = true);
    try {
      await ref.read(authRepositoryProvider).logoutAll();
      ref.read(sessionSignalProvider).expire();
      if (mounted) context.go('/welcome');
    } on ApiFailure catch (error) {
      showTopNotification(error.message, success: false);
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> changePassword() async {
    if (busy) return;
    final form = GlobalKey<FormState>();
    final current = TextEditingController();
    final next = TextEditingController();
    final confirm = TextEditingController();
    final values = await showDialog<({String current, String next})>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change password'),
        content: Form(
          key: form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                  controller: current,
                  obscureText: true,
                  decoration:
                      const InputDecoration(labelText: 'Current password'),
                  validator: (value) =>
                      value == null || value.isEmpty ? 'Required' : null),
              TextFormField(
                  controller: next,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'New password'),
                  validator: (value) => value != null &&
                          value.length >= 12 &&
                          RegExp(r'[a-z]').hasMatch(value) &&
                          RegExp(r'[A-Z]').hasMatch(value) &&
                          RegExp(r'\d').hasMatch(value) &&
                          RegExp(r'[^A-Za-z\d]').hasMatch(value)
                      ? null
                      : 'Use 12+ characters with upper, lower, number and symbol'),
              TextFormField(
                  controller: confirm,
                  obscureText: true,
                  decoration:
                      const InputDecoration(labelText: 'Confirm new password'),
                  validator: (value) =>
                      value == next.text ? null : 'Passwords do not match'),
            ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(
                    context, (current: current.text, next: next.text));
              }
            },
            child: const Text('Change'),
          ),
        ],
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    current.dispose();
    next.dispose();
    confirm.dispose();
    if (values == null || !mounted) return;
    setState(() => busy = true);
    try {
      await ref
          .read(authRepositoryProvider)
          .changePassword(values.current, values.next);
      showTopNotification('Password changed. Other devices were signed out.');
      if (mounted) refresh();
    } on ApiFailure catch (error) {
      showTopNotification(error.message, success: false);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authenticated =
        ref.watch(sessionProvider).phase == SessionPhase.authenticated;
    return Scaffold(
      appBar: AppBar(title: const Text('Account security')),
      body: !authenticated
          ? Center(
              child: FilledButton(
                onPressed: () => context.push('/login'),
                child: const Text('Sign in to manage security'),
              ),
            )
          : RefreshIndicator(
              onRefresh: () async {
                refresh();
                await sessions;
              },
              child: ListView(padding: const EdgeInsets.all(20), children: [
                const Text('Withdrawal verification',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text(
                    'Every withdrawal requires a fresh six-digit code. An authenticator app is recommended; email codes are available when email delivery is configured.'),
                const SizedBox(height: 10),
                FutureBuilder<JsonObject>(
                  future: verification,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return ListTile(
                        title: const Text('Authenticator app'),
                        subtitle: Text(snapshot.hasError
                            ? 'Verification settings are temporarily unavailable.'
                            : 'Loading verification settings…'),
                      );
                    }
                    final enabled =
                        snapshot.data?['authenticatorEnabled'] == true;
                    return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ListTile(
                            leading: Icon(enabled
                                ? Icons.verified_user_outlined
                                : Icons.security_outlined),
                            title: Text(enabled
                                ? 'Authenticator app enabled'
                                : 'Set up authenticator app'),
                            subtitle: Text(enabled
                                ? 'Use a new code for every withdrawal.'
                                : 'Google Authenticator, Microsoft Authenticator, and compatible apps work.'),
                            trailing: enabled
                                ? null
                                : TextButton(
                                    onPressed: busy ? null : beginAuthenticator,
                                    child: const Text('Set up')),
                          ),
                          if (pendingSecret != null) ...[
                            const Text(
                                'Add a new account in your authenticator app and enter this setup key:'),
                            const SizedBox(height: 8),
                            SelectableText(pendingSecret!,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.2)),
                            const SizedBox(height: 8),
                            TextField(
                                controller: authenticatorCode,
                                keyboardType: TextInputType.number,
                                maxLength: 6,
                                decoration: const InputDecoration(
                                    labelText: 'Six-digit code')),
                            FilledButton(
                                onPressed: busy ? null : confirmAuthenticator,
                                child: const Text('Enable authenticator')),
                          ],
                          ListTile(
                            leading: const Icon(Icons.mail_outline),
                            title: const Text('Email verification'),
                            subtitle: Text(snapshot.data?['emailAvailable'] ==
                                    true
                                ? 'Codes can be sent to ${snapshot.data?['email']}.'
                                : 'Email codes will be available once mail delivery is configured.'),
                          ),
                        ]);
                  },
                ),
                const SizedBox(height: 20),
                const Text('Active sessions',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text(
                    'Review devices signed in to your account. Revoke any session you do not recognize.'),
                const SizedBox(height: 16),
                FutureBuilder<List<JsonObject>>(
                  future: sessions,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData && !snapshot.hasError) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return ListTile(
                        title: const Text('Could not load sessions'),
                        subtitle: Text(snapshot.error is ApiFailure
                            ? (snapshot.error! as ApiFailure).message
                            : 'Check your connection and try again.'),
                        trailing: IconButton(
                            onPressed: refresh,
                            icon: const Icon(Icons.refresh)),
                      );
                    }
                    final items = snapshot.data!;
                    if (items.isEmpty) {
                      return const Text('No active sessions found.');
                    }
                    return Column(
                      children: [
                        for (final item in items)
                          Card(
                            child: ListTile(
                              leading: const Icon(Icons.devices_outlined),
                              title: Text(((item['device'] as Map?)?['name'] ??
                                      item['userAgent'] ??
                                      'Unknown device')
                                  .toString()),
                              subtitle: Text(
                                  'Last active: ${item['lastSeenAt'] ?? 'Unknown'}\n${(item['device'] as Map?)?['platform'] ?? ''}'),
                              isThreeLine: true,
                              trailing: TextButton(
                                onPressed: busy
                                    ? null
                                    : () => revoke(item['id'] as String),
                                child: const Text('Revoke'),
                              ),
                            ),
                          )
                      ],
                    );
                  },
                ),
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: busy ? null : changePassword,
                  icon: const Icon(Icons.lock_reset_outlined),
                  label: const Text('Change password'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: busy ? null : signOutAll,
                  icon: const Icon(Icons.logout),
                  label: const Text('Sign out all devices'),
                ),
                const SizedBox(height: 18),
                const Text('Your data',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Privacy policy'),
                  onTap: () => launchUrl(
                    Uri.parse('https://zettax.app/privacy.html'),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.person_remove_outlined),
                  title: const Text('Request account deletion'),
                  subtitle: const Text('Open the web request path'),
                  onTap: () => launchUrl(
                    Uri.parse('https://zettax.app/account-deletion.html'),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                    'Changing your password signs out other devices. Never share your password, setup key, or verification codes.'),
              ]),
            ),
    );
  }
}
