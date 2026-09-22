import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:primevest_mobile/app/design_system.dart';
import 'package:primevest_mobile/core/account/account_mode_selector.dart';
import 'package:primevest_mobile/core/account/account_models.dart';
import 'package:primevest_mobile/core/app_providers.dart';
import 'package:primevest_mobile/demo/models.dart';
import 'package:primevest_mobile/demo/providers.dart';
import 'package:primevest_mobile/features/home/home_screen.dart';
import 'package:primevest_mobile/features/shared/market_widgets.dart';
import 'package:primevest_mobile/market/market_data_providers.dart';
import 'package:primevest_mobile/market/market_data_status.dart';

class AssetDetailScreen extends ConsumerStatefulWidget {
  const AssetDetailScreen({super.key, required this.assetId});
  final String assetId;

  @override
  ConsumerState<AssetDetailScreen> createState() => _AssetDetailScreenState();
}

class _AssetDetailScreenState extends ConsumerState<AssetDetailScreen> {
  String interval = '1h';

  @override
  Widget build(BuildContext context) {
    final assets = ref.watch(assetsProvider).value ?? const <MarketAsset>[];
    final asset = assets.where((item) => item.id == widget.assetId).firstOrNull;
    if (asset == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final market = ref.watch(marketProvider);
    final request = (assetId: asset.id, interval: interval, limit: 90);
    final liveSeries = ref.watch(liveCandlesProvider(request));
    final liveSamples = liveSeries.value?.candles
        .map((candle) => candle.close)
        .toList(growable: false);
    final hasLiveData = liveSamples?.isNotEmpty == true;
    final price = hasLiveData
        ? liveSamples!.last
        : market.prices[asset.id] ?? asset.price;
    final favorite = market.favorites.contains(asset.id);
    final demoSelected =
        ref.watch(selectedAccountModeProvider) == AccountMode.demo;
    final config = ref.watch(systemConfigProvider).valueOrNull ??
        PublicSystemConfig.failClosed;
    final tradingAvailable =
        config.tradingAvailableFor(ref.watch(selectedAccountModeProvider));
    final positive = asset.changePercent >= 0;
    return Scaffold(
      appBar: AppBar(title: Text(asset.symbol), actions: [
        const AccountModeSelector(),
        IconButton(
            tooltip: 'Refresh market data',
            onPressed: () => ref.invalidate(liveCandlesProvider(request)),
            icon: const Icon(Icons.refresh_rounded)),
        IconButton(
            onPressed: () =>
                ref.read(marketProvider.notifier).toggleFavorite(asset.id),
            icon: Icon(
                favorite ? Icons.star_rounded : Icons.star_border_rounded,
                color: favorite ? PrimeVestDesignSystem.primaryGold : null)),
      ]),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Row(children: [
          AssetIcon(asset: asset),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(asset.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 18)),
                Text(
                    '${asset.assetClass} • ${liveSeries.value?.freshness == 'SAMPLED' ? 'Sampled real prices' : liveSeries.value?.freshness == 'SIMULATED' ? 'Simulated virtual-market data' : hasLiveData ? 'External market data' : 'Simulated fallback'}',
                    style: const TextStyle(
                        color: PrimeVestDesignSystem.textMuted, fontSize: 12)),
              ])),
        ]),
        const SizedBox(height: 22),
        Text(
            liveSeries.value?.freshness == 'SAMPLED'
                ? 'Latest available price · sampled every 15 minutes'
                : liveSeries.value?.freshness == 'SIMULATED'
                    ? 'Simulated chart — not a live market quote'
                    : hasLiveData
                        ? 'External display reference'
                        : 'Simulated display reference',
            style: const TextStyle(
                color: PrimeVestDesignSystem.textMuted, fontSize: 11)),
        const SizedBox(height: 4),
        Text(price.toStringAsFixed(asset.precision),
            style: const TextStyle(
                fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: -1)),
        Text(
            '${positive ? '+' : ''}${asset.changePercent.toStringAsFixed(2)}% today',
            style: TextStyle(
                color: positive
                    ? PrimeVestDesignSystem.positive
                    : PrimeVestDesignSystem.negative,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 20),
        PriceChart(
          asset: asset,
          candlesOverride: liveSeries.value?.candles,
          onLoadOlder: () =>
              ref.read(liveCandlesProvider(request).notifier).loadOlder(),
        ),
        const SizedBox(height: 14),
        Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: ['1m', '5m', '15m', '30m', '1h', '4h', '1d', '1w', '1M']
                .map((value) => InkWell(
                      onTap: () => setState(() => interval = value),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 8),
                        child: Text(value,
                            style: TextStyle(
                                color: interval == value
                                    ? PrimeVestDesignSystem.primaryGold
                                    : PrimeVestDesignSystem.textMuted,
                                fontWeight: interval == value
                                    ? FontWeight.w800
                                    : FontWeight.w500)),
                      ),
                    ))
                .toList(growable: false)),
        const SizedBox(height: 24),
        MarketDataStatus(
          series: liveSeries,
          requestedInterval: interval,
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: tradingAvailable
              ? () {
                  ref.read(selectedAssetProvider.notifier).state = asset.id;
                  context.go('/home?tab=2');
                }
              : null,
          icon: const Icon(Icons.bolt),
          label: Text(demoSelected
              ? 'Trade in demo'
              : !tradingAvailable
                  ? 'REAL trading unavailable'
                  : config.usesVirtualFunds
                      ? 'Trade with virtual balance'
                      : 'Trade in REAL account'),
        ),
      ]),
    );
  }
}
