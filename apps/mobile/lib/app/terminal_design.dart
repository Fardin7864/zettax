import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:primevest_mobile/app/design_system.dart';
import 'package:primevest_mobile/core/account/account_mode_selector.dart';
import 'package:primevest_mobile/core/account/account_models.dart';
import 'package:primevest_mobile/core/app_providers.dart';
import 'package:primevest_mobile/demo/providers.dart';

abstract final class TerminalDesign {
  static const gold = PrimeVestDesignSystem.primaryGold;
  static const muted = PrimeVestDesignSystem.textMuted;
  static const edge = Color(0xFF40382F);
  static const surface = Color(0xFF24221E);
  static const background = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF2C281F), Color(0xFF1C1C1C), Color(0xFF1C1C1C)],
      stops: [0, .32, 1]);
  static ThemeData theme(ThemeData base) => base.copyWith(
        scaffoldBackgroundColor: Colors.transparent,
        textTheme: base.textTheme.apply(fontFamily: 'DMSans').copyWith(
              headlineSmall: const TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: Colors.white),
              titleLarge: const TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Colors.white),
              titleMedium: const TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white),
              bodyMedium: const TextStyle(
                  fontFamily: 'DMSans',
                  fontSize: 13,
                  color: Colors.white,
                  height: 1.5),
            ),
        appBarTheme: base.appBarTheme.copyWith(
            toolbarHeight: 72,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            titleTextStyle: const TextStyle(
                fontFamily: 'Manrope',
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.white)),
        cardTheme: const CardThemeData(
            color: surface,
            elevation: 0,
            margin: EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(13)),
                side: BorderSide(color: edge))),
        dividerTheme:
            const DividerThemeData(color: edge, thickness: 1, space: 1),
        inputDecorationTheme: base.inputDecorationTheme.copyWith(
            fillColor: const Color(0xFF211F1C),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: const BorderSide(color: edge)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: const BorderSide(color: edge)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: const BorderSide(color: gold))),
        filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                textStyle: const TextStyle(
                    fontFamily: 'DMSans',
                    fontSize: 12,
                    fontWeight: FontWeight.w700))),
        outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 44),
                side: const BorderSide(color: edge),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                textStyle:
                    const TextStyle(fontFamily: 'DMSans', fontSize: 12))),
        bottomSheetTheme: const BottomSheetThemeData(
            backgroundColor: surface,
            showDragHandle: true,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)))),
      );
}

class TerminalPanel extends StatelessWidget {
  const TerminalPanel(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(20),
      this.glow = false});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool glow;
  @override
  Widget build(BuildContext context) => Container(
      padding: padding,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: TerminalDesign.edge),
          gradient: LinearGradient(
              begin: glow ? Alignment.topRight : Alignment.topLeft,
              end: Alignment.bottomLeft,
              colors: glow
                  ? const [Color(0xFF3B3020), TerminalDesign.surface]
                  : const [Color(0xFF2B2822), Color(0xFF211F1C)])),
      child: child);
}

class TerminalEyebrow extends StatelessWidget {
  const TerminalEyebrow(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          fontFamily: 'DMSans',
          fontSize: 10,
          height: 1.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
          color: TerminalDesign.muted));
}

class TerminalControl extends StatelessWidget {
  const TerminalControl(
      {super.key,
      required this.label,
      required this.child,
      required this.onTap});
  final String label;
  final Widget child;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Tooltip(
      message: label,
      child: Semantics(
          button: true,
          label: label,
          child: SizedBox(
              width: 40,
              height: 44,
              child: Center(
                  child: Material(
                      color: TerminalDesign.surface,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(9),
                          side: const BorderSide(color: TerminalDesign.edge)),
                      child: InkWell(
                          onTap: onTap,
                          borderRadius: BorderRadius.circular(9),
                          child: SizedBox(
                              width: 35,
                              height: 35,
                              child: Center(child: child))))))));
}

Future<void> terminalSheet(
        BuildContext context, String title, List<Widget> children) =>
    showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (c) => SafeArea(
            child: SingleChildScrollView(
                child: Padding(
                    padding: EdgeInsets.fromLTRB(
                        20, 0, 20, 24 + MediaQuery.viewInsetsOf(c).bottom),
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: Theme.of(c).textTheme.titleLarge),
                          const SizedBox(height: 16),
                          ...children
                        ])))));

class TerminalHeader extends ConsumerWidget {
  const TerminalHeader(
      {super.key,
      required this.title,
      this.onBack,
      this.actions = const [],
      this.onProfile});
  final String title;
  final VoidCallback? onBack, onProfile;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final user = ref.watch(currentUserProvider).valueOrNull;
    final name = user?.profile?.fullName.trim() ?? '';
    final initials = name.isNotEmpty
        ? name
            .split(RegExp(r'\s+'))
            .take(2)
            .map((s) => s.characters.first)
            .join()
            .toUpperCase()
        : session.user?.email.characters.firstOrNull?.toUpperCase() ?? 'Z';
    void profile() => terminalSheet(context, 'Your account', [
          const Row(children: [
            Expanded(child: Text('Account mode')),
            AccountModeSelector()
          ]),
          ListTile(
              contentPadding: EdgeInsets.zero,
              leading:
                  const Icon(Icons.person_outline, color: TerminalDesign.gold),
              title: const Text('View profile'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pop(context);
                if (onProfile != null) {
                  onProfile!();
                } else {
                  context.go('/home?tab=4');
                }
              }),
        ]);
    return SafeArea(
        bottom: false,
        child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 18, 14, 21),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      if (onBack == null)
                        const TerminalEyebrow('TRADING TERMINAL')
                      else
                        Row(children: [
                          SizedBox(
                              width: 26,
                              height: 22,
                              child: IconButton(
                                  key: const ValueKey('trade-back-button'),
                                  tooltip: 'Back',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints.tightFor(
                                      width: 26, height: 22),
                                  onPressed: onBack,
                                  icon:
                                      const Icon(Icons.arrow_back, size: 16))),
                          const SizedBox(width: 4),
                          const Expanded(
                              child: Text('TRADING TERMINAL',
                                  style: TextStyle(
                                      fontSize: 8,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.1,
                                      color: TerminalDesign.muted)))
                        ]),
                      const SizedBox(height: 5),
                      Text(title,
                          style: const TextStyle(
                              fontFamily: 'Manrope',
                              fontSize: 22,
                              height: 1.5,
                              fontWeight: FontWeight.w600))
                    ])),
                TerminalControl(
                    label: 'Help and guidance',
                    onTap: () => terminalSheet(context, 'How can we help?', [
                          const Text(
                              'Explore markets and learn with virtual trading.',
                              style: TextStyle(color: TerminalDesign.muted)),
                          for (final item in [
                            ('Markets', '/home?tab=1'),
                            ('Community', '/community'),
                            ('Help & education', '/education'),
                            ('Security', '/security')
                          ])
                            ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(item.$1),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () {
                                  Navigator.pop(context);
                                  context.push(item.$2);
                                }),
                        ]),
                    child: const Text('?',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: TerminalDesign.gold))),
                const SizedBox(width: 8),
                TerminalControl(
                    label: 'Account updates',
                    onTap: () => terminalSheet(context, 'Account updates', [
                          const Icon(Icons.notifications_none,
                              color: TerminalDesign.gold),
                          const SizedBox(height: 12),
                          Text(ref
                                  .read(fundingRealtimeNoticeProvider)
                                  ?.message ??
                              'No recent account updates on this device.')
                        ]),
                    child:
                        const Icon(Icons.notifications_none_rounded, size: 21)),
                const SizedBox(width: 8),
                TerminalControl(
                    label: 'Profile and account mode',
                    onTap: profile,
                    child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                            color: TerminalDesign.gold.withValues(alpha: .10),
                            borderRadius: BorderRadius.circular(7)),
                        child: Text(initials,
                            style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: TerminalDesign.gold)))),
              ]),
              if (actions.isNotEmpty)
                Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: actions)),
            ])));
  }
}

class TerminalBalance extends ConsumerWidget {
  const TerminalBalance(
      {super.key, this.label = 'TOTAL ASSETS', this.tradeActions = false});
  final String label;
  final bool tradeActions;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(selectedAccountModeProvider);
    final auth = ref.watch(sessionProvider).phase == SessionPhase.authenticated;
    final demo = ref.watch(demoAccountProvider);
    final wallet = ref
        .watch(accountsProvider)
        .valueOrNull
        ?.where((a) => a.mode == mode)
        .firstOrNull
        ?.wallets
        .firstOrNull;
    final total = auth
        ? double.tryParse(wallet?.equity ?? '')
        : mode == AccountMode.demo
            ? (demo.availablePaisa + demo.lockedPaisa) / 100
            : null;
    void funding(bool withdraw) =>
        context.push(auth ? (withdraw ? '/withdraw' : '/cash-in') : '/login');
    return TerminalPanel(
        glow: true,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          LayoutBuilder(builder: (context, bounds) {
            final data =
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TerminalEyebrow(label),
              const SizedBox(height: 9),
              Text(
                  total == null
                      ? '—'
                      : NumberFormat.currency(symbol: '\$', decimalDigits: 2)
                          .format(total),
                  style: const TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 28,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(
                  '${mode == AccountMode.demo ? 'Demo' : 'Virtual'} account · USD',
                  style: const TextStyle(
                      fontSize: 10, color: TerminalDesign.muted))
            ]);
            final button = FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: () => funding(false),
                child: const Text('＋ Add funds'));
            return !tradeActions &&
                    bounds.maxWidth > 270 &&
                    MediaQuery.textScalerOf(context).scale(1) < 1.4
                ? Row(children: [
                    Expanded(child: data),
                    const SizedBox(width: 10),
                    button
                  ])
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        data,
                        if (!tradeActions) ...[
                          const SizedBox(height: 12),
                          button
                        ]
                      ]);
          }),
          if (tradeActions) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 18, runSpacing: 8, children: [
              _fundingAction(Icons.add, 'Deposit', () => funding(false)),
              _fundingAction(Icons.north_east, 'Withdraw', () => funding(true)),
              _fundingAction(Icons.account_balance_wallet_outlined, 'Portfolio',
                  () => context.go('/home?tab=3')),
            ])
          ],
        ]));
  }

  Widget _fundingAction(IconData icon, String text, VoidCallback action) =>
      InkWell(
          onTap: action,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
              child: Column(children: [
                Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                        color: TerminalDesign.gold.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(8)),
                    child: Icon(icon, size: 18, color: TerminalDesign.gold)),
                const SizedBox(height: 5),
                Text(text,
                    style: const TextStyle(
                        fontSize: 10, color: TerminalDesign.muted))
              ])));
}

/// Route title treatment used by the reference's supporting account screens.
class TerminalAppTitle extends StatelessWidget {
  const TerminalAppTitle(this.title, {super.key});
  final String title;
  @override
  Widget build(BuildContext context) => kIsWeb
      ? Text(title)
      : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
              const Text('TRADING TERMINAL',
                  style: TextStyle(
                      fontFamily: 'DMSans',
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4,
                      color: TerminalDesign.muted)),
              const SizedBox(height: 3),
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 20,
                      fontWeight: FontWeight.w600))
            ]);
}
