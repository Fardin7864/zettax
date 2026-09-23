import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:primevest_mobile/app/design_system.dart';
import 'package:primevest_mobile/demo/models.dart';
import 'package:primevest_mobile/demo/providers.dart';
import 'package:primevest_mobile/features/shared/ohlc_chart.dart';
import 'package:primevest_mobile/market/market_data_api.dart';
import 'package:primevest_mobile/market/market_data_providers.dart';
import 'package:primevest_mobile/market/display_currency.dart';

class DemoBadge extends StatelessWidget {
  const DemoBadge({super.key});
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
            color: const Color(0x28F8B425),
            borderRadius: BorderRadius.circular(20)),
        child: const Text('DEMO',
            style: TextStyle(
                color: PrimeVestDesignSystem.primaryGold,
                fontWeight: FontWeight.w800,
                fontSize: 10,
                letterSpacing: .8)),
      );
}

class MarketTile extends ConsumerWidget {
  const MarketTile(
      {super.key,
      required this.asset,
      required this.onTap,
      this.favorite,
      this.onFavorite});
  final MarketAsset asset;
  final VoidCallback onTap;
  final bool? favorite;
  final VoidCallback? onFavorite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final series = ref.watch(liveCandlesProvider(
      (
        assetId: asset.id,
        interval: asset.assetClass == 'Crypto' ? '1m' : '1d',
        limit: 90,
      ),
    ));
    final candles = series.valueOrNull?.candles;
    final price = candles?.lastOrNull?.close;
    final change = candles != null &&
            candles.length > 1 &&
            candles.first.close != 0
        ? (candles.last.close - candles.first.close) / candles.first.close * 100
        : null;
    final positive = (change ?? 0) >= 0;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 6),
          child: Row(children: [
            AssetIcon(asset: asset),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(asset.symbol,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(asset.name,
                      style: const TextStyle(
                          color: PrimeVestDesignSystem.textMuted,
                          fontSize: 12)),
                ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(
                  price == null
                      ? '—'
                      : formatDisplayPrice(
                          value: price,
                          precision: asset.precision,
                          quoteAsset: asset.quoteAsset,
                        ),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(
                  change == null
                      ? (series.isLoading ? 'Loading…' : 'Unavailable')
                      : '${positive ? '+' : ''}${change.toStringAsFixed(2)}%',
                  style: TextStyle(
                      color: positive
                          ? PrimeVestDesignSystem.positive
                          : PrimeVestDesignSystem.negative,
                      fontSize: 12)),
            ]),
            if (onFavorite != null)
              IconButton(
                  onPressed: onFavorite,
                  icon: Icon(
                      favorite == true
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      color: favorite == true
                          ? PrimeVestDesignSystem.primaryGold
                          : PrimeVestDesignSystem.textMuted)),
          ]),
        ),
      ),
    );
  }
}

class AssetIcon extends StatelessWidget {
  const AssetIcon({super.key, required this.asset, this.size = 42});
  final MarketAsset asset;
  final double size;

  static const _crypto =
      'https://cdn.jsdelivr.net/gh/spothq/cryptocurrency-icons@master/128/color';
  static const _flags = 'https://flagcdn.com/w80';

  static List<String> imageUrlsFor(String id) => switch (id) {
        'btc-usd' => ['$_crypto/btc.png'],
        'eth-usd' => ['$_crypto/eth.png'],
        'sol-usd' => ['$_crypto/sol.png'],
        'xrp-usd' => ['$_crypto/xrp.png'],
        'ada-usd' => ['$_crypto/ada.png'],
        'doge-usd' => ['$_crypto/doge.png'],
        'avax-usd' => ['$_crypto/avax.png'],
        'dot-usd' => ['$_crypto/dot.png'],
        'link-usd' => ['$_crypto/link.png'],
        'ltc-usd' => ['$_crypto/ltc.png'],
        'bch-usd' => ['$_crypto/bch.png'],
        'trx-usd' => ['$_crypto/trx.png'],
        'uni-usd' => ['$_crypto/uni.png'],
        'atom-usd' => ['$_crypto/atom.png'],
        'near-usd' => [
            'https://cryptologos.cc/logos/near-protocol-near-logo.png?v=040'
          ],
        'shib-usd' => [
            'https://cryptologos.cc/logos/shiba-inu-shib-logo.png?v=040'
          ],
        'apt-usd' => ['https://cryptologos.cc/logos/aptos-apt-logo.png?v=040'],
        'sui-usd' => ['https://cryptologos.cc/logos/sui-sui-logo.png?v=040'],
        'pepe-usd' => ['https://cryptologos.cc/logos/pepe-pepe-logo.png?v=040'],
        'eur-usd' => ['$_flags/eu.png', '$_flags/us.png'],
        'gbp-usd' => ['$_flags/gb.png', '$_flags/us.png'],
        'usd-jpy' => ['$_flags/us.png', '$_flags/jp.png'],
        'aud-usd' => ['$_flags/au.png', '$_flags/us.png'],
        'aapl' => [
            'https://www.google.com/s2/favicons?domain=apple.com&sz=128'
          ],
        'msft' => [
            'https://www.google.com/s2/favicons?domain=microsoft.com&sz=128'
          ],
        'nvda' => [
            'https://www.google.com/s2/favicons?domain=nvidia.com&sz=128'
          ],
        'tsla' => [
            'https://www.google.com/s2/favicons?domain=tesla.com&sz=128'
          ],
        'spx' => [
            'https://www.google.com/s2/favicons?domain=spglobal.com&sz=128'
          ],
        'ndx' => [
            'https://www.google.com/s2/favicons?domain=nasdaq.com&sz=128'
          ],
        'dax' => [
            'https://www.google.com/s2/favicons?domain=deutsche-boerse.com&sz=128'
          ],
        'xau-usd' => [
            'https://commons.wikimedia.org/wiki/Special:FilePath/Chip_gold_bullion_bar.jpg?width=128'
          ],
        'xag-usd' => [
            'https://commons.wikimedia.org/wiki/Special:FilePath/Johnson_Matthey_500_grammes_silver_bullion.jpg?width=128'
          ],
        'oil-usd' => [
            'https://commons.wikimedia.org/wiki/Special:FilePath/Oil_barrel.png?width=128'
          ],
        _ => const [],
      };

  @override
  Widget build(BuildContext context) {
    final urls = imageUrlsFor(asset.id);
    return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
            color: _color.withValues(alpha: .14),
            borderRadius: BorderRadius.circular(size * .3)),
        clipBehavior: Clip.antiAlias,
        child: urls.isEmpty
            ? _fallback()
            : urls.length == 2
                ? Stack(children: [
                    Positioned(
                        left: 3,
                        top: size * .18,
                        child: _image(urls[0], size * .65)),
                    Positioned(
                        right: 2,
                        bottom: size * .13,
                        child: _image(urls[1], size * .55)),
                  ])
                : _image(urls.first, size * .86));
  }

  Widget _image(String url, double dimension) => ClipOval(
        child: Image.network(
          url,
          width: dimension,
          height: dimension,
          fit: BoxFit.cover,
          cacheWidth: 128,
          errorBuilder: (_, __, ___) => _fallback(),
        ),
      );

  Widget _fallback() => Text(
        asset.symbol.substring(0, min(2, asset.symbol.length)),
        style: TextStyle(
            color: _color, fontSize: size * .26, fontWeight: FontWeight.w900),
      );
  Color get _color => switch (asset.assetClass) {
        'Crypto' => const Color(0xFFF8B425),
        'Forex' => const Color(0xFF60A5FA),
        'Stocks' => const Color(0xFFA78BFA),
        'Indices' => const Color(0xFF2DD4BF),
        _ => const Color(0xFFF0C36D),
      };
}

class PriceChart extends ConsumerWidget {
  const PriceChart({
    super.key,
    required this.asset,
    this.compact = false,
    this.candlesOverride,
    this.onLoadOlder,
    this.tradeMarkers = const [],
    this.lineMode = false,
    this.allowFallback = true,
  });
  final MarketAsset asset;
  final bool compact;
  final List<MarketCandle>? candlesOverride;
  final VoidCallback? onLoadOlder;
  final List<ChartTradeMarker> tradeMarkers;
  final bool lineMode;
  final bool allowFallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final market = ref.watch(marketProvider);
    final current = market.prices[asset.id] ?? asset.price;
    final external = candlesOverride;
    if (external?.isNotEmpty != true && !allowFallback) {
      return Container(
        height: compact ? 190 : 270,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF211F1D),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF302D29)),
        ),
        child: const Text(
          'Waiting for market data…',
          style: TextStyle(color: PrimeVestDesignSystem.textMuted),
        ),
      );
    }
    final candles = external?.isNotEmpty == true
        ? external!.map(ChartCandle.fromMarket).toList(growable: false)
        : _fallbackCandles(
            market.history[asset.id] ?? [asset.price, current],
          );
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
          color: const Color(0xFF211F1D),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF302D29))),
      clipBehavior: Clip.antiAlias,
      child: OhlcChart(
        candles: candles,
        precision: asset.precision,
        compact: compact,
        onLoadOlder: onLoadOlder,
        tradeMarkers: tradeMarkers,
        lineMode: lineMode,
      ),
    );
  }

  List<ChartCandle> _fallbackCandles(List<double> samples) {
    final start =
        DateTime.now().toUtc().subtract(Duration(minutes: samples.length));
    return List.generate(samples.length, (index) {
      final close = samples[index];
      final open = index == 0 ? close : samples[index - 1];
      final spread = max(close.abs() * .0008, .00001);
      return ChartCandle(
        time: start.add(Duration(minutes: index)),
        open: open,
        high: max(open, close) + spread,
        low: max(.000001, min(open, close) - spread),
        close: close,
      );
    }, growable: false);
  }
}

class MiniStat extends StatelessWidget {
  const MiniStat({super.key, required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(
                color: PrimeVestDesignSystem.textMuted, fontSize: 11)),
        const SizedBox(height: 4),
        SizedBox(
          width: double.infinity,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ]);
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(
      {super.key, required this.title, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
            child: Text(title,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800))),
        if (action != null)
          TextButton(
              onPressed: onAction,
              child: Text(action!, style: const TextStyle(fontSize: 12))),
      ]);
}

class CategoryCard extends StatelessWidget {
  const CategoryCard(
      {super.key,
      required this.icon,
      required this.title,
      required this.subtitle,
      this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 132,
          margin: const EdgeInsets.only(right: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
              color: PrimeVestDesignSystem.surfaceDark,
              borderRadius: BorderRadius.circular(16)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: PrimeVestDesignSystem.primaryGold, size: 21),
            const Spacer(),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(subtitle,
                style: const TextStyle(
                    color: PrimeVestDesignSystem.textMuted, fontSize: 10)),
          ]),
        ),
      );
}

class EducationCard extends StatelessWidget {
  const EducationCard({super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: const Color(0xFF20272A),
            borderRadius: BorderRadius.circular(18)),
        child: const Row(children: [
          Icon(Icons.school_outlined, color: Color(0xFF67E8F9), size: 30),
          SizedBox(width: 15),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('Learn before you trade',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                SizedBox(height: 5),
                Text('Demo activity uses virtual funds and simulated prices.',
                    style: TextStyle(
                        color: PrimeVestDesignSystem.textMuted,
                        fontSize: 12,
                        height: 1.4)),
              ])),
          Icon(Icons.chevron_right),
        ]),
      );
}

class TradeButton extends StatelessWidget {
  const TradeButton(
      {super.key,
      required this.label,
      required this.icon,
      required this.onPressed,
      this.negative = false});
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool negative;
  @override
  Widget build(BuildContext context) => FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label, style: const TextStyle(fontSize: 13)),
        style: FilledButton.styleFrom(
            backgroundColor: negative
                ? const Color(0xFF44262C)
                : PrimeVestDesignSystem.primaryGold,
            foregroundColor: negative
                ? PrimeVestDesignSystem.negative
                : const Color(0xFF18140C)),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState(
      {super.key, required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;
  @override
  Widget build(BuildContext context) => Center(
          child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 48, color: PrimeVestDesignSystem.textMuted),
          const SizedBox(height: 14),
          Text(title,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 7),
          Text(body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: PrimeVestDesignSystem.textMuted, height: 1.4)),
        ]),
      ));
}

class ActivityCard extends StatelessWidget {
  const ActivityCard(
      {super.key,
      required this.title,
      required this.badge,
      required this.value,
      required this.positive,
      required this.subtitle,
      this.asset,
      this.action});
  final String title;
  final String badge;
  final String value;
  final bool positive;
  final String subtitle;
  final MarketAsset? asset;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Card(
          child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                if (asset != null) ...[
                  AssetIcon(asset: asset!, size: 34),
                  const SizedBox(width: 10),
                ],
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text(badge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: PrimeVestDesignSystem.primaryGold,
                              fontSize: 10,
                              fontWeight: FontWeight.w800)),
                    ])),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                    child: Text(value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: positive
                                ? PrimeVestDesignSystem.positive
                                : PrimeVestDesignSystem.negative,
                            fontWeight: FontWeight.w800))),
                if (action != null) action!,
              ]),
              const SizedBox(height: 5),
              Text(subtitle,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: PrimeVestDesignSystem.textMuted, fontSize: 11)),
            ]),
      ));
}

class ProfileTile extends StatelessWidget {
  const ProfileTile(
      {super.key,
      required this.icon,
      required this.title,
      required this.subtitle,
      this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(vertical: 3),
        leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
                color: PrimeVestDesignSystem.surfaceDark,
                borderRadius: BorderRadius.circular(12)),
            child:
                Icon(icon, color: PrimeVestDesignSystem.primaryGold, size: 21)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle,
            style: const TextStyle(
                color: PrimeVestDesignSystem.textMuted, fontSize: 11)),
        trailing: const Icon(Icons.chevron_right),
      );
}

String timeAgo(DateTime time) {
  final difference = DateTime.now().difference(time);
  if (difference.inSeconds < 60) return '${difference.inSeconds}s ago';
  if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
  return '${difference.inHours}h ago';
}
