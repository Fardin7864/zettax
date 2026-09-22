import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:primevest_mobile/core/app_providers.dart';
import 'package:primevest_mobile/market/market_data_api.dart';
import 'package:primevest_mobile/market/market_realtime_client.dart';

typedef MarketDataRequest = ({String assetId, String interval, int limit});

final marketDataApiProvider = Provider<MarketDataApi>((ref) => MarketDataApi());
final marketRealtimeClientProvider = Provider<MarketRealtimeClient>(
  (ref) => MarketRealtimeClient(tokenStore: ref.watch(tokenStoreProvider)),
);

final liveCandlesProvider = StateNotifierProvider.autoDispose.family<
    MarketCandleHistoryController,
    AsyncValue<MarketCandleSeries>,
    MarketDataRequest>((ref, request) {
  return MarketCandleHistoryController(
    api: ref.read(marketDataApiProvider),
    realtime: ref.read(marketRealtimeClientProvider),
    request: request,
  );
});

class MarketCandleHistoryController
    extends StateNotifier<AsyncValue<MarketCandleSeries>> {
  MarketCandleHistoryController({
    required MarketDataApi api,
    required MarketRealtimeClient realtime,
    required MarketDataRequest request,
  })  : _api = api,
        _realtime = realtime,
        _request = request,
        super(const AsyncLoading()) {
    _bootstrap();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) {
        final lastEvent = _lastRealtimeEventAt;
        if (!_realtimeConnected ||
            lastEvent == null ||
            DateTime.now().difference(lastEvent) >
                const Duration(seconds: 45)) {
          _loadLatest(preserveHistory: true);
        }
      },
    );
  }

  final MarketDataApi _api;
  final MarketRealtimeClient _realtime;
  final MarketDataRequest _request;
  late final Timer _refreshTimer;
  MarketRealtimeSubscription? _realtimeSubscription;
  DateTime? _lastRealtimeEventAt;
  bool _realtimeConnected = false;
  bool _loadingLatest = false;
  bool _loadingOlder = false;

  Future<void> _bootstrap() async {
    await _loadLatest();
    if (!mounted) return;
    _realtimeSubscription = await _realtime.subscribe(
      instrumentId: _request.assetId,
      interval: _request.interval,
      onCandle: _applyRealtime,
      onSequenceGap: () => _loadLatest(preserveHistory: true),
      onConnectionChanged: (connected) {
        _realtimeConnected = connected;
      },
    );
  }

  void _applyRealtime(MarketRealtimeUpdate update) {
    if (!mounted) return;
    final current = state.valueOrNull;
    if (current == null) return;
    _lastRealtimeEventAt = DateTime.now();
    state = AsyncData(current.mergeRealtime(
      candle: update.candle,
      latestProviderTimestamp: update.providerTimestamp,
      latestReceivedAt: update.receivedAt,
    ));
  }

  Future<void> refresh() => _loadLatest(preserveHistory: true);

  Future<void> loadOlder() async {
    final current = state.valueOrNull;
    final cursor = current?.nextCursor;
    if (current == null || cursor == null || _loadingOlder) return;
    _loadingOlder = true;
    try {
      final older = await _api.fetchCandles(
        _request.assetId,
        _request.interval,
        limit: _request.limit,
        before: cursor,
      );
      if (mounted) state = AsyncData(current.mergeOlder(older));
    } catch (error, stackTrace) {
      // Keep the visible page usable when only historical pagination fails.
      if (mounted && state.valueOrNull == null) {
        state = AsyncError(error, stackTrace);
      }
    } finally {
      _loadingOlder = false;
    }
  }

  Future<void> _loadLatest({bool preserveHistory = false}) async {
    if (_loadingLatest) return;
    _loadingLatest = true;
    final previous = state.valueOrNull;
    if (previous == null) state = const AsyncLoading();
    try {
      final latest = await _api.fetchCandles(
        _request.assetId,
        _request.interval,
        limit: _request.limit,
      );
      if (!mounted) return;
      state = AsyncData(
        preserveHistory && previous != null
            ? latest.mergeOlder(previous)
            : latest,
      );
    } catch (error, stackTrace) {
      if (mounted && previous == null) state = AsyncError(error, stackTrace);
    } finally {
      _loadingLatest = false;
    }
  }

  @override
  void dispose() {
    _refreshTimer.cancel();
    _realtimeSubscription?.dispose();
    super.dispose();
  }
}
