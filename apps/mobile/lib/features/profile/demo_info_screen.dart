import 'package:flutter/material.dart';
import 'package:primevest_mobile/app/design_system.dart';
import 'package:primevest_mobile/features/shared/market_widgets.dart';

class DemoInfoScreen extends StatelessWidget {
  const DemoInfoScreen({
    super.key,
    required this.title,
    required this.icon,
    required this.summary,
    required this.items,
  });

  final String title;
  final IconData icon;
  final String summary;
  final List<String> items;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: const [DemoBadge(), SizedBox(width: 12)],
        ),
        body: ListView(
          padding: const EdgeInsets.all(22),
          children: [
            CircleAvatar(
              radius: 34,
              backgroundColor:
                  PrimeVestDesignSystem.primaryGold.withValues(alpha: .14),
              child: Icon(icon,
                  color: PrimeVestDesignSystem.primaryGold, size: 32),
            ),
            const SizedBox(height: 20),
            Text(summary,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: PrimeVestDesignSystem.textMuted,
                    height: 1.5,
                    fontSize: 15)),
            const SizedBox(height: 24),
            ...items.map((item) => Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      const Icon(Icons.check_circle_outline,
                          color: PrimeVestDesignSystem.primaryGold, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                          child:
                              Text(item, style: const TextStyle(height: 1.35))),
                    ]),
                  ),
                )),
          ],
        ),
      );
}
