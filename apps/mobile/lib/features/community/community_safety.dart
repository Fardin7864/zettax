import 'package:primevest_mobile/app/terminal_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:primevest_mobile/core/app_providers.dart';
import 'package:primevest_mobile/core/api/api_contract.dart';
import 'package:primevest_mobile/app/top_notification.dart';

Map<String, dynamic> _map(dynamic data) =>
    Map<String, dynamic>.from(data as Map);

Future<bool> ensureCommunityRules(BuildContext context, WidgetRef ref) async {
  final response =
      await ref.read(apiClientProvider).get('/community/rules/status', _map);
  if (response.data['accepted'] == true) return true;
  if (!context.mounted) return false;
  final agreed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
            title:
                Text(response.data['title']?.toString() ?? 'Community rules'),
            content: SingleChildScrollView(
                child: Text(response.data['text']?.toString() ?? '')),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Accept and continue'))
            ],
          ));
  if (agreed != true) return false;
  await ref.read(apiClientProvider).post(
      '/community/rules/accept', {'version': response.data['version']}, _map);
  return true;
}

class CommunitySafetyMenu extends ConsumerWidget {
  const CommunitySafetyMenu(
      {super.key,
      required this.targetType,
      required this.targetId,
      required this.onChanged});
  final String targetType;
  final String targetId;
  final VoidCallback onChanged;

  Future<void> act(BuildContext context, WidgetRef ref, String action) async {
    try {
      if (action == 'BLOCK') {
        final agreed = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
                  title: const Text('Block this user?'),
                  content: const Text(
                      'Their posts and comments will be hidden, and community interactions between you will be blocked. You can manage blocked users from the Community menu.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: const Text('Block user'))
                  ],
                ));
        if (agreed != true) return;
        await ref.read(apiClientProvider).post('/community/blocks',
            {'targetType': targetType, 'targetId': targetId}, _map);
        showTopNotification('User blocked.');
        onChanged();
        return;
      }
      final details = await showDialog<String>(
          context: context,
          builder: (_) =>
              _CommunityReportDialog(reportUser: action == 'REPORT_USER'));
      if (details == null) return;
      await ref.read(apiClientProvider).post(
          action == 'REPORT_USER'
              ? '/community/reports/author'
              : '/community/reports',
          {'targetType': targetType, 'targetId': targetId, 'reason': details},
          _map);
      showTopNotification('Report received for moderation.');
    } catch (error) {
      showTopNotification(
          error is ApiFailure
              ? error.message
              : 'This action could not be completed.',
          success: false);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => PopupMenuButton<String>(
        tooltip: 'Community safety',
        onSelected: (value) => act(context, ref, value),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'REPORT', child: Text('Report content')),
          PopupMenuItem(value: 'REPORT_USER', child: Text('Report user')),
          PopupMenuItem(value: 'BLOCK', child: Text('Block user'))
        ],
      );
}

class CommunityBlockedUsersScreen extends ConsumerStatefulWidget {
  const CommunityBlockedUsersScreen({super.key});
  @override
  ConsumerState<CommunityBlockedUsersScreen> createState() =>
      _CommunityBlockedUsersState();
}

class _CommunityBlockedUsersState
    extends ConsumerState<CommunityBlockedUsersScreen> {
  late Future<List<dynamic>> rows;
  @override
  void initState() {
    super.initState();
    rows = load();
  }

  Future<List<dynamic>> load() async => (await ref
          .read(apiClientProvider)
          .get('/community/blocks', (value) => value as List))
      .data;
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const TerminalAppTitle('Blocked users')),
      body: FutureBuilder<List<dynamic>>(
          future: rows,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                  child: TextButton(
                      onPressed: () => setState(() => rows = load()),
                      child: const Text('Retry loading blocked users')));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.data!.isEmpty) {
              return const Center(child: Text('No blocked users.'));
            }
            return ListView(
                children: snapshot.data!.map((raw) {
              final row = _map(raw);
              final name = (row['blocked'] as Map?)?['profile']?['fullName']
                      ?.toString() ??
                  'Zettax member';
              return ListTile(
                  title: Text(name),
                  trailing: TextButton(
                      onPressed: () async {
                        try {
                          await ref.read(apiClientProvider).delete(
                              '/community/blocks/${row['blockedId']}', _map);
                          if (mounted) setState(() => rows = load());
                        } catch (error) {
                          showTopNotification(
                              error is ApiFailure
                                  ? error.message
                                  : 'Could not unblock this user.',
                              success: false);
                        }
                      },
                      child: const Text('Unblock')));
            }).toList());
          }));
}

class _CommunityReportDialog extends StatefulWidget {
  const _CommunityReportDialog({required this.reportUser});
  final bool reportUser;
  @override
  State<_CommunityReportDialog> createState() => _CommunityReportDialogState();
}

class _CommunityReportDialogState extends State<_CommunityReportDialog> {
  final reason = TextEditingController();
  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.reportUser ? 'Report this user' : 'Report content'),
        content: TextField(
            controller: reason,
            maxLength: 1000,
            maxLines: 4,
            decoration: const InputDecoration(
                labelText: 'What is wrong?',
                hintText:
                    'Scam, phishing, harassment, unsafe content or another issue')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () {
                if (reason.text.trim().isNotEmpty) {
                  Navigator.pop(context, reason.text.trim());
                }
              },
              child: const Text('Send report'))
        ],
      );
}
