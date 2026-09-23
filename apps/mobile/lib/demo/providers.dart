import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:primevest_mobile/demo/mock_api.dart';
import 'package:primevest_mobile/demo/models.dart';
import 'package:primevest_mobile/market/market_data_api.dart';

final mockApiProvider = Provider<MockPrimeVestApi>((ref) {
  return const MockPrimeVestApi();
});

final assetsProvider = FutureProvider<List<MarketAsset>>((ref) async {
  try {
    final catalogue = await MarketDataApi().fetchInstruments();
    final demoAssets = await ref.read(mockApiProvider).fetchInstruments();
    return catalogue.map((item) {
      final seed = demoAssets.where((seed) => seed.id == item.id).firstOrNull;
      return MarketAsset(
          id: item.id,
          symbol: item.symbol,
          name: item.name,
          assetClass: item.assetClass,
          price: seed?.price ?? 0,
          changePercent: seed?.changePercent ?? 0,
          precision: item.precision,
          quoteAsset: item.quoteAsset);
    }).toList(growable: false);
  } catch (_) {
    // The bundled catalogue is an offline fallback only. Prices never come
    // from it when rendering the live Markets list.
    return ref.read(mockApiProvider).fetchInstruments();
  }
});

class MarketState {
  const MarketState(
      {this.prices = const {},
      this.history = const {},
      this.favorites = const {'btc-usd', 'xau-usd'},
      this.sequence = 0});
  final Map<String, double> prices;
  final Map<String, List<double>> history;
  final Set<String> favorites;
  final int sequence;

  MarketState copyWith(
          {Map<String, double>? prices,
          Map<String, List<double>>? history,
          Set<String>? favorites,
          int? sequence}) =>
      MarketState(
        prices: prices ?? this.prices,
        history: history ?? this.history,
        favorites: favorites ?? this.favorites,
        sequence: sequence ?? this.sequence,
      );
}

class MockMarketController extends StateNotifier<MarketState> {
  MockMarketController(this.assets)
      : super(MarketState(prices: {
          for (final asset in assets) asset.id: asset.price
        }, history: {
          for (var assetIndex = 0; assetIndex < assets.length; assetIndex++)
            assets[assetIndex].id: List<double>.generate(42, (pointIndex) {
              final asset = assets[assetIndex];
              final wave = sin((pointIndex + assetIndex * 3) * .34) * .004;
              final trend =
                  (pointIndex - 21) * asset.changePercent.sign * .00011;
              return asset.price * (1 + wave + trend);
            })
        })) {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }
  final List<MarketAsset> assets;
  late final Timer _timer;

  void toggleFavorite(String assetId) {
    final favorites = {...state.favorites};
    favorites.contains(assetId)
        ? favorites.remove(assetId)
        : favorites.add(assetId);
    state = state.copyWith(favorites: favorites);
  }

  void _tick() {
    final sequence = state.sequence + 1;
    final prices = <String, double>{};
    final history = <String, List<double>>{};
    for (var index = 0; index < assets.length; index++) {
      final asset = assets[index];
      final current = state.prices[asset.id] ?? asset.price;
      final wave = sin((sequence + index * 3) * .37) * .00065;
      final drift = cos((sequence + index) * .11) * .00018;
      prices[asset.id] = max(.00001, current * (1 + wave + drift));
      history[asset.id] = [
        ...?state.history[asset.id],
        prices[asset.id]!,
      ].skip(max(0, (state.history[asset.id]?.length ?? 0) + 1 - 90)).toList();
    }
    state =
        state.copyWith(prices: prices, history: history, sequence: sequence);
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }
}

final marketProvider =
    StateNotifierProvider<MockMarketController, MarketState>((ref) {
  final assets = ref.watch(assetsProvider).value ?? const <MarketAsset>[];
  return MockMarketController(assets);
});

class DemoAccountState {
  const DemoAccountState({
    this.availablePaisa = 100000,
    this.positions = const [],
    this.history = const [],
    this.contracts = const [],
    this.transactions = const [],
  });
  final int availablePaisa;
  final List<DemoPosition> positions;
  final List<DemoTradeRecord> history;
  final List<TimedContract> contracts;
  final List<DemoTransaction> transactions;

  int get lockedPaisa =>
      positions.fold(0, (sum, item) => sum + item.stakePaisa) +
      contracts
          .where((item) => item.result == ContractResult.pending)
          .fold(0, (sum, item) => sum + item.investmentPaisa);

  DemoAccountState copyWith({
    int? availablePaisa,
    List<DemoPosition>? positions,
    List<DemoTradeRecord>? history,
    List<TimedContract>? contracts,
    List<DemoTransaction>? transactions,
  }) =>
      DemoAccountState(
        availablePaisa: availablePaisa ?? this.availablePaisa,
        positions: positions ?? this.positions,
        history: history ?? this.history,
        contracts: contracts ?? this.contracts,
        transactions: transactions ?? this.transactions,
      );
}

class DemoAccountController extends StateNotifier<DemoAccountState> {
  DemoAccountController(this.ref) : super(const DemoAccountState()) {
    _timer =
        Timer.periodic(const Duration(seconds: 1), (_) => _settleExpired());
  }
  final Ref ref;
  late final Timer _timer;
  int _nextId = 1;

  bool openPosition(String assetId, TradeSide side, int stakePaisa) {
    final price = ref.read(marketProvider).prices[assetId];
    if (price == null || stakePaisa <= 0 || stakePaisa > state.availablePaisa) {
      return false;
    }
    final position = DemoPosition(
      id: 'P${_nextId++}',
      assetId: assetId,
      side: side,
      stakePaisa: stakePaisa,
      quantity: (stakePaisa / 100) / price,
      entryPrice: price,
      openedAt: DateTime.now(),
    );
    state = state.copyWith(
      availablePaisa: state.availablePaisa - stakePaisa,
      positions: [...state.positions, position],
      transactions: [
        _transaction(
            '${side == TradeSide.buy ? 'BUY' : 'SELL'} position opened',
            -stakePaisa),
        ...state.transactions
      ],
    );
    return true;
  }

  void closePosition(String positionId) {
    final position =
        state.positions.where((item) => item.id == positionId).firstOrNull;
    if (position == null) return;
    final price = ref.read(marketProvider).prices[position.assetId] ??
        position.entryPrice;
    final direction = position.side == TradeSide.buy ? 1 : -1;
    final pnlPaisa =
        ((price - position.entryPrice) * position.quantity * 100 * direction)
            .round();
    final record = DemoTradeRecord(
        position: position,
        exitPrice: price,
        pnlPaisa: pnlPaisa,
        closedAt: DateTime.now());
    state = state.copyWith(
      availablePaisa:
          max(0, state.availablePaisa + position.stakePaisa + pnlPaisa),
      positions:
          state.positions.where((item) => item.id != positionId).toList(),
      history: [record, ...state.history],
      transactions: [
        _transaction('Position closed', position.stakePaisa + pnlPaisa),
        ...state.transactions
      ],
    );
  }

  bool openContract(String assetId, ContractDirection direction,
      int investmentPaisa, Duration duration) {
    final price = ref.read(marketProvider).prices[assetId];
    if (price == null ||
        investmentPaisa <= 0 ||
        investmentPaisa > state.availablePaisa) {
      return false;
    }
    final now = ref.read(mockApiProvider).serverNow();
    final market = ref.read(marketProvider);
    final contract = TimedContract(
      id: 'T${_nextId++}',
      assetId: assetId,
      direction: direction,
      investmentPaisa: investmentPaisa,
      entryPrice: price,
      entryTimestamp: now,
      expiryTimestamp: now.add(duration),
      payoutRate: .82,
      priceSource: MockPrimeVestApi.providerName,
      entrySequence: market.sequence,
    );
    state = state.copyWith(
      availablePaisa: state.availablePaisa - investmentPaisa,
      contracts: [contract, ...state.contracts],
      transactions: [
        _transaction(
            '${direction == ContractDirection.up ? 'UP' : 'DOWN'} contract',
            -investmentPaisa),
        ...state.transactions
      ],
    );
    return true;
  }

  void reset() {
    state = DemoAccountState(
        transactions: [_transaction('Demo account reset', 100000)]);
  }

  void _settleExpired() {
    final now = ref.read(mockApiProvider).serverNow();
    var available = state.availablePaisa;
    var changed = false;
    final transactions = [...state.transactions];
    final contracts = state.contracts.map((contract) {
      if (contract.result != ContractResult.pending ||
          contract.expiryTimestamp.isAfter(now)) {
        return contract;
      }
      final market = ref.read(marketProvider);
      final price = market.prices[contract.assetId] ?? contract.entryPrice;
      final comparison = price.compareTo(contract.entryPrice);
      final result = comparison == 0
          ? ContractResult.draw
          : (contract.direction == ContractDirection.up
                  ? comparison > 0
                  : comparison < 0)
              ? ContractResult.win
              : ContractResult.loss;
      final credit = result == ContractResult.win
          ? (contract.investmentPaisa * (1 + contract.payoutRate)).round()
          : result == ContractResult.draw
              ? contract.investmentPaisa
              : 0;
      available += credit;
      transactions.insert(0,
          _transaction('Timed contract ${result.name.toUpperCase()}', credit));
      changed = true;
      return contract.settle(price, market.sequence, now, result);
    }).toList();
    if (changed) {
      state = state.copyWith(
          availablePaisa: available,
          contracts: contracts,
          transactions: transactions);
    }
  }

  DemoTransaction _transaction(String title, int amountPaisa) =>
      DemoTransaction(
        id: 'TX${_nextId++}',
        title: title,
        amountPaisa: amountPaisa,
        createdAt: DateTime.now(),
      );

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }
}

final demoAccountProvider =
    StateNotifierProvider<DemoAccountController, DemoAccountState>(
        DemoAccountController.new);

String usdFromCents(int paisa) {
  final sign = paisa < 0 ? '-' : '';
  final value = paisa.abs() / 100;
  final parts = value.toStringAsFixed(2).split('.');
  final digits = parts.first;
  final grouped =
      digits.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (match) => ',');
  return '$sign\$$grouped.${parts.last}';
}
