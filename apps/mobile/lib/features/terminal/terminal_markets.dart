import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:primevest_mobile/app/terminal_design.dart';
import 'package:primevest_mobile/app/design_system.dart';
import 'package:primevest_mobile/demo/models.dart';
import 'package:primevest_mobile/demo/providers.dart';
import 'package:primevest_mobile/features/shared/market_widgets.dart';
import 'package:primevest_mobile/market/display_currency.dart';
import 'package:primevest_mobile/market/market_data_providers.dart';

const terminalMarketCategories = [
  'All',
  'Favorites',
  'Crypto',
  'Stocks',
  'Forex',
  'Indices',
  'Commodities'
];

class TerminalTabs extends StatelessWidget {
  const TerminalTabs(
      {super.key,
      required this.items,
      required this.selected,
      required this.onSelected});
  final List<String> items;
  final String selected;
  final ValueChanged<String> onSelected;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (final item in items)
          Padding(
              padding: const EdgeInsets.only(right: 22),
              child: InkWell(
                  onTap: () => onSelected(item),
                  child: Container(
                      constraints: const BoxConstraints(minHeight: 44),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          border: Border(
                              bottom: BorderSide(
                                  color: selected == item
                                      ? TerminalDesign.gold
                                      : Colors.transparent,
                                  width: 1.5))),
                      child: Text(item,
                          style: TextStyle(
                              fontSize: 11,
                              color: selected == item
                                  ? TerminalDesign.gold
                                  : TerminalDesign.muted)))))
      ]));
}

class TerminalMarketsPage extends ConsumerStatefulWidget {
  const TerminalMarketsPage({super.key, required this.onTrade});
  final VoidCallback onTrade;
  @override
  ConsumerState<TerminalMarketsPage> createState() =>
      _TerminalMarketsPageState();
}

class _TerminalMarketsPageState extends ConsumerState<TerminalMarketsPage> {
  String category = 'All', search = '';
  @override
  Widget build(BuildContext context) {
    final data = ref.watch(assetsProvider);
    final favorites = ref.watch(marketProvider).favorites;
    final filtered = (data.valueOrNull ?? <MarketAsset>[])
        .where((a) => _matches(a, search, category, favorites))
        .toList();
    return RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(assetsProvider);
          for (final a in filtered.take(10)) {
            ref.invalidate(liveCandlesProvider((
              assetId: a.id,
              interval: a.assetClass == 'Crypto' ? '1m' : '1d',
              limit: 90
            )));
          }
        },
        child: CustomScrollView(slivers: [
          const SliverToBoxAdapter(child: TerminalHeader(title: 'Markets')),
          SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              sliver: SliverToBoxAdapter(
                  child: TerminalPanel(
                      glow: true,
                      padding: const EdgeInsets.all(23),
                      child: LayoutBuilder(builder: (context, bounds) {
                        final copy = Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const TerminalEyebrow('LIVE MARKETS'),
                              const SizedBox(height: 10),
                              const Text('Explore every market',
                                  style: TextStyle(
                                      fontFamily: 'Manrope',
                                      fontSize: 20,
                                      fontWeight: FontWeight.w600)),
                              const Text(
                                  'Crypto, equities, and forex in one searchable workspace.',
                                  style: TextStyle(
                                      color: TerminalDesign.muted,
                                      fontSize: 11,
                                      height: 1.5))
                            ]);
                        final action = FilledButton(
                            style: FilledButton.styleFrom(
                                minimumSize: const Size(0, 44)),
                            onPressed: widget.onTrade,
                            child: const Text('Open\nterminal',
                                textAlign: TextAlign.center));
                        return bounds.maxWidth < 270 ||
                                MediaQuery.textScalerOf(context).scale(1) > 1.3
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                    copy,
                                    const SizedBox(height: 12),
                                    action
                                  ])
                            : Row(children: [
                                Expanded(child: copy),
                                const SizedBox(width: 12),
                                action
                              ]);
                      })))),
          SliverPadding(
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
              sliver: SliverToBoxAdapter(
                  child: Column(children: [
                TextField(
                    style: const TextStyle(fontSize: 12),
                    onChanged: (v) => setState(() => search = v),
                    decoration: const InputDecoration(
                        hintText: 'Search assets',
                        prefixIcon: Icon(Icons.search, size: 19),
                        isDense: true)),
                const SizedBox(height: 6),
                TerminalTabs(
                    items: terminalMarketCategories,
                    selected: category,
                    onSelected: (v) => setState(() => category = v)),
              ]))),
          SliverPadding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
              sliver: DecoratedSliver(
                  decoration: BoxDecoration(
                      color: TerminalDesign.surface,
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: TerminalDesign.edge)),
                  sliver: SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                              (context, index) {
                        if (index == 0) {
                          return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 15),
                              child: Row(children: [
                                Expanded(
                                    flex: 5,
                                    child: Text('Asset',
                                        style: TextStyle(
                                            fontSize: 9,
                                            color: TerminalDesign.muted))),
                                Expanded(
                                    flex: 4,
                                    child: Text('Price (USD)',
                                        style: TextStyle(
                                            fontSize: 9,
                                            color: TerminalDesign.muted))),
                                Expanded(
                                    flex: 2,
                                    child: Text('Move',
                                        style: TextStyle(
                                            fontSize: 9,
                                            color: TerminalDesign.muted),
                                        textAlign: TextAlign.right))
                              ]));
                        }
                        if (filtered.isEmpty) {
                          return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 32),
                              child: Column(children: [
                                Text(
                                    data.isLoading
                                        ? 'Loading markets…'
                                        : data.hasError
                                            ? 'Markets could not be loaded.'
                                            : 'No matching assets.',
                                    style: const TextStyle(
                                        color: TerminalDesign.muted)),
                                if (data.hasError)
                                  TextButton(
                                      onPressed: () =>
                                          ref.invalidate(assetsProvider),
                                      child: const Text('Retry'))
                              ]));
                        }
                        final asset = filtered[index - 1];
                        return TerminalMarketRow(
                            asset: asset,
                            onTap: () => context.push('/asset/${asset.id}'),
                            favorite: favorites.contains(asset.id),
                            onFavorite: () => ref
                                .read(marketProvider.notifier)
                                .toggleFavorite(asset.id));
                      },
                              childCount: filtered.isEmpty
                                  ? 2
                                  : filtered.length + 1))))),
          const SliverPadding(
              padding: EdgeInsets.fromLTRB(14, 0, 14, 24),
              sliver: SliverToBoxAdapter(
                  child: Text(
                      'Move shows the loaded price window, not a 24-hour return. Market prices are for display.',
                      style: TextStyle(
                          fontSize: 9, color: TerminalDesign.muted)))),
        ]));
  }
}

bool _matches(
        MarketAsset a, String search, String category, Set<String> favorites) =>
    ('${a.symbol} ${a.name}'
        .toLowerCase()
        .replaceAll('/', '')
        .contains(search.trim().toLowerCase().replaceAll('/', ''))) &&
    (category == 'All' ||
        (category == 'Favorites'
            ? favorites.contains(a.id)
            : a.assetClass == category));

class TerminalMarketRow extends ConsumerWidget {
  const TerminalMarketRow(
      {super.key,
      required this.asset,
      required this.onTap,
      this.favorite = false,
      this.onFavorite,
      this.selected = false,
      this.compact = false});
  final MarketAsset asset;
  final VoidCallback onTap;
  final bool favorite, selected, compact;
  final VoidCallback? onFavorite;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final series = ref
        .watch(liveCandlesProvider((
          assetId: asset.id,
          interval: asset.assetClass == 'Crypto' ? '1m' : '1d',
          limit: 90
        )))
        .valueOrNull;
    final candles = series?.candles;
    final price = candles?.lastOrNull?.close;
    final move =
        candles != null && candles.length > 1 && candles.first.close > 0
            ? (candles.last.close / candles.first.close - 1) * 100
            : null;
    final positive = (move ?? 0) >= 0;
    final priceLabel = price == null
        ? '—'
        : formatDisplayPrice(
            value: price,
            precision: asset.precision,
            quoteAsset: asset.quoteAsset);
    final change = Text(
        move == null
            ? '—'
            : '${positive ? '+' : ''}${move.toStringAsFixed(2)}%',
        style: TextStyle(
            fontSize: 10,
            color: move == null
                ? TerminalDesign.muted
                : positive
                    ? PrimeVestDesignSystem.positive
                    : PrimeVestDesignSystem.negative));
    return Container(
        decoration: BoxDecoration(
            color: selected
                ? TerminalDesign.gold.withValues(alpha: .08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(selected ? 9 : 0),
            border: const Border(top: BorderSide(color: TerminalDesign.edge))),
        child: InkWell(
            onTap: onTap,
            child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: LayoutBuilder(builder: (context, bounds) {
                  final label = Row(children: [
                    AssetIcon(asset: asset, size: 28),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(asset.symbol,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w700)),
                          Text(asset.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 8, color: TerminalDesign.muted))
                        ]))
                  ]);
                  return Row(children: [
                    Expanded(flex: 5, child: label),
                    const SizedBox(width: 6),
                    Expanded(
                        flex: 4,
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(priceLabel,
                                  style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700)),
                              if (compact ||
                                  MediaQuery.textScalerOf(context).scale(1) >
                                      1.4)
                                change
                            ])),
                    if (!compact &&
                        MediaQuery.textScalerOf(context).scale(1) <= 1.4)
                      Expanded(
                          flex: 2,
                          child: Align(
                              alignment: Alignment.centerRight, child: change)),
                    if (onFavorite != null)
                      SizedBox(
                          width: 30,
                          child: IconButton(
                              tooltip:
                                  favorite ? 'Remove favorite' : 'Add favorite',
                              padding: EdgeInsets.zero,
                              onPressed: onFavorite,
                              icon: Icon(
                                  favorite
                                      ? Icons.star_rounded
                                      : Icons.star_outline_rounded,
                                  size: 17,
                                  color: favorite
                                      ? TerminalDesign.gold
                                      : TerminalDesign.muted)))
                  ]);
                }))));
  }
}

class TerminalMarketPicker extends ConsumerStatefulWidget {
  const TerminalMarketPicker(
      {super.key,
      required this.assets,
      required this.selectedId,
      required this.onSelected});
  final List<MarketAsset> assets;
  final String selectedId;
  final ValueChanged<String> onSelected;
  @override
  ConsumerState<TerminalMarketPicker> createState() =>
      _TerminalMarketPickerState();
}

class _TerminalMarketPickerState extends ConsumerState<TerminalMarketPicker> {
  String search = '', category = 'All';
  bool expanded = false;
  @override
  Widget build(BuildContext context) {
    final favorites = ref.watch(marketProvider).favorites;
    final assets = widget.assets
        .where((a) => _matches(a, search, category, favorites))
        .toList();
    return TerminalPanel(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Markets', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
              onChanged: (v) => setState(() => search = v),
              decoration: const InputDecoration(
                  hintText: 'Search assets',
                  prefixIcon: Icon(Icons.search, size: 18),
                  isDense: true)),
          TerminalTabs(
              items: terminalMarketCategories,
              selected: category,
              onSelected: (v) => setState(() => category = v)),
          const SizedBox(height: 5),
          if (assets.isEmpty)
            const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No matching assets.',
                    style: TextStyle(color: TerminalDesign.muted))),
          for (final asset in assets.take(expanded ? assets.length : 6))
            TerminalMarketRow(
                compact: true,
                selected: asset.id == widget.selectedId,
                asset: asset,
                favorite: favorites.contains(asset.id),
                onFavorite: () =>
                    ref.read(marketProvider.notifier).toggleFavorite(asset.id),
                onTap: () => widget.onSelected(asset.id)),
          if (assets.length > 6)
            TextButton(
                onPressed: () => setState(() => expanded = !expanded),
                child: Text(expanded
                    ? 'Show fewer'
                    : 'Show all ${assets.length} markets')),
        ]));
  }
}
