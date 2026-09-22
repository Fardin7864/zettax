import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
  bool busy = false;

  @override
  void initState() {
    super.initState();
    sessions = ref.read(sessionProvider).phase == SessionPhase.authenticated
        ? ref.read(authRepositoryProvider).sessions()
        : Future.value(const []);
  }

  void refresh() => setState(() {
        sessions = ref.read(authRepositoryProvider).sessions();
      });

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
                const SizedBox(height: 12),
                const Text(
                    'Changing your password signs out other devices. Two-factor authentication is not available yet. Never share your password or sign-in codes.'),
              ]),
            ),
    );
  }
}
