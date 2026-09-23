import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';
import 'package:primevest_mobile/app/brand_logo.dart';
import 'package:primevest_mobile/app/design_system.dart';
import 'package:primevest_mobile/l10n/app_localizations.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
        body: SafeArea(
            child: Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Padding(
                      padding:
                          const EdgeInsets.all(PrimeVestDesignSystem.spacing24),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Spacer(),
                            const ZettaxMark(height: 78),
                            const SizedBox(height: 28),
                            Text(l10n.welcomeTitle,
                                style: Theme.of(context)
                                    .textTheme
                                    .displaySmall
                                    ?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        height: 1.05)),
                            const SizedBox(height: 14),
                            Text(l10n.welcomeBody,
                                style: const TextStyle(
                                    color: PrimeVestDesignSystem.textMuted,
                                    fontSize: 16,
                                    height: 1.5)),
                            const Spacer(),
                            FilledButton(
                                onPressed: () => context.go('/home'),
                                child: Text(l10n.tryDemo)),
                            const SizedBox(height: 12),
                            OutlinedButton(
                                onPressed: () => context.push('/register'),
                                style: OutlinedButton.styleFrom(
                                    minimumSize: const Size.fromHeight(54)),
                                child: Text(l10n.createAccount)),
                            TextButton(
                                onPressed: () => context.push('/login'),
                                child: Center(child: Text(l10n.login))),
                            if (kIsWeb)
                              OutlinedButton.icon(
                                onPressed: () => launchUrl(
                                  Uri.parse(
                                      'https://zettax.app/downloads/zettax-latest.apk'),
                                ),
                                icon: const Icon(Icons.android),
                                label: const Text('Download Android app'),
                              ),
                          ]),
                    )))));
  }
}
