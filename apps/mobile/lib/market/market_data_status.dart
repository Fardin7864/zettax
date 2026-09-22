import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:primevest_mobile/app/design_system.dart';
import 'package:primevest_mobile/market/market_data_api.dart';

class MarketDataStatus extends StatelessWidget {
  const MarketDataStatus({
    super.key,
    required this.series,
    required this.requestedInterval,
    this.compact = false,
  });

  final AsyncValue<MarketCandleSeries> series;
  final String requestedInterval;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final data = series.value;
    final usingExternalData = data != null && data.candles.isNotEmpty;
    final color = usingExternalData
        ? const Color(0xFF67E8F9)
        : PrimeVestDesignSystem.primaryGold;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: PrimeVestDesignSystem.surfaceDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: .22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            usingExternalData ? Icons.public_rounded : Icons.cloud_off_rounded,
            color: color,
            size: compact ? 18 : 21,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  usingExternalData
                      ? '${data.provider} • ${marketFreshnessLabel(data.freshness)} • ${data.delivery.toLowerCase()}'
                      : series.isLoading
                          ? 'Loading external display data'
                          : 'Market data unavailable',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: compact ? 11 : 12,
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(height: 3),
                  Text(
                    usingExternalData
                        ? _externalDescription(data)
                        : _fallbackDescription(),
                    style: const TextStyle(
                      color: PrimeVestDesignSystem.textMuted,
                      fontSize: 10.5,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _externalDescription(MarketCandleSeries data) {
    final effective = data.effectiveInterval == requestedInterval
        ? '${data.effectiveInterval} candles'
        : '$requestedInterval requested; ${data.effectiveInterval} supplied';
    final synthetic = data.isSyntheticOhlc
        ? ' • synthetic OHLC from reference observations'
        : '';
    return '$effective • latest source observation ${marketDataAge(data.providerTimestamp)}'
        '$synthetic • received ${marketDataAge(data.receivedAt)}';
  }

  String _fallbackDescription() {
    if (series.isLoading) {
      return 'Connecting to the configured market-data provider.';
    }
    return 'No provider price is being shown. Some asset classes require a configured Twelve Data key.';
  }
}

String marketFreshnessLabel(String freshness) => switch (freshness) {
      'DISPLAY_LIVE' => 'live display feed',
      'REAL_TIME' => 'near real-time',
      'DELAYED' => 'delayed',
      'REFERENCE_DAILY' => 'daily reference',
      _ => freshness.toLowerCase().replaceAll('_', ' '),
    };

String marketDataAge(DateTime receivedAt, {DateTime? now}) {
  final age = (now ?? DateTime.now().toUtc()).difference(receivedAt.toUtc());
  if (age.isNegative || age.inSeconds < 5) return 'just now';
  if (age.inSeconds < 60) return '${age.inSeconds}s ago';
  if (age.inMinutes < 60) return '${age.inMinutes}m ago';
  return '${age.inHours}h ago';
}
