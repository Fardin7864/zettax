import 'dart:math';
import 'dart:convert';

import 'package:primevest_mobile/core/account/account_models.dart';
import 'package:primevest_mobile/core/api/api_contract.dart';
import 'package:primevest_mobile/core/api/primevest_api_client.dart';
import 'package:primevest_mobile/core/trading/trading_models.dart';
import 'package:primevest_mobile/core/trading/pending_contract_store.dart';

class TradingRepository {
  TradingRepository(this._client,
      {PendingContractStore? pendingStore, this.userId = 'test'})
      : _pendingStore = pendingStore ?? MemoryPendingContractStore();
  final PrimeVestApiClient _client;
  final PendingContractStore _pendingStore;
  final String userId;
  bool _contractInFlight = false;
  bool _preparingContract = false;

  Future<JsonObject?> pendingTimedContract() async {
    final raw = await _pendingStore.read(userId);
    return raw == null ? null : _object(jsonDecode(raw));
  }

  Future<TimedContract> retryPendingTimedContract() async {
    final pending = await pendingTimedContract();
    if (pending == null) throw StateError('No pending contract');
    return _sendTimedContract(pending);
  }

  Future<TimedContract> _sendTimedContract(JsonObject pending) async {
    if (_contractInFlight) {
      throw const ApiFailure(
          code: 'CONTRACT_IN_PROGRESS',
          message: 'Please wait for the previous request.',
          requestId: '');
    }
    _contractInFlight = true;
    try {
      final response = await _client.post('/timed-contracts', pending['body'],
          (value) => TimedContract.fromJson(_object(value)),
          idempotencyKey: requireString(pending, 'key'),
          receiveTimeout: const Duration(seconds: 60));
      await _pendingStore.clear(userId);
      return response.data;
    } on ApiFailure catch (error) {
      // Network/server uncertainty keeps the original command for explicit recovery.
      if (error.statusCode == 400 ||
          error.statusCode == 403 ||
          error.code == 'CONTRACT_PRICE_UNAVAILABLE' ||
          error.code == 'TRADING_TERMS_CHANGED') {
        await _pendingStore.clear(userId);
      }
      rethrow;
    } finally {
      _contractInFlight = false;
    }
  }

  Future<TradingOrder> createMarketOrder({
    required AccountMode mode,
    required String instrumentId,
    required String side,
    required String quantity,
  }) async {
    final nonce =
        '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 31)}';
    final response = await _client.post(
      '/orders',
      {
        'accountMode': mode.apiValue,
        'instrumentId': instrumentId,
        'clientOrderId': 'mobile-$nonce',
        'side': side,
        'orderType': 'MARKET',
        'quantity': quantity,
      },
      (value) => TradingOrder.fromJson(_object(value)),
      idempotencyKey: 'order:$nonce',
      receiveTimeout: const Duration(seconds: 60),
    );
    return response.data;
  }

  Future<List<TradingPosition>> positions(AccountMode mode,
      {String? status}) async {
    final response = await _client.get(
      '/positions',
      (value) => requireList(_object(value)['items'], TradingPosition.fromJson),
      queryParameters: {
        'accountMode': mode.apiValue,
        if (status != null) 'status': status,
      },
    );
    return response.data;
  }

  Future<TradingPosition> closePosition(String positionId) async {
    final nonce = DateTime.now().microsecondsSinceEpoch.toString();
    final response = await _client.post(
      '/positions/$positionId/close',
      null,
      (value) => TradingPosition.fromJson(_object(value)),
      idempotencyKey: 'close:$nonce',
      receiveTimeout: const Duration(seconds: 60),
    );
    return response.data;
  }

  Future<TimedContract> createTimedContract({
    required AccountMode mode,
    required String instrumentId,
    required String direction,
    required String investmentAmount,
    required int durationSeconds,
    required String expectedProfitFeeRate,
  }) async {
    if (_preparingContract || _contractInFlight) {
      throw const ApiFailure(
          code: 'CONTRACT_IN_PROGRESS',
          message: 'Please wait for the previous request.',
          requestId: '');
    }
    _preparingContract = true;
    try {
      if (await pendingTimedContract() != null) {
        throw const ApiFailure(
            code: 'CONTRACT_RECOVERY_REQUIRED',
            message:
                'Resolve the previous trade request before opening another.',
            requestId: '');
      }
      final nonce =
          '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 31)}';
      final pending = <String, dynamic>{
        'key': 'timed:$nonce',
        'body': {
          'accountMode': mode.apiValue,
          'instrumentId': instrumentId,
          'direction': direction,
          'investmentAmount': investmentAmount,
          'durationSeconds': durationSeconds,
          'expectedProfitFeeRate': expectedProfitFeeRate,
        }
      };
      await _pendingStore.write(userId, jsonEncode(pending));
      return await _sendTimedContract(pending);
    } finally {
      _preparingContract = false;
    }
  }

  Future<List<TimedContract>> timedContracts(AccountMode mode) async {
    final response = await _client.get(
      '/timed-contracts',
      (value) => requireList(_object(value)['items'], TimedContract.fromJson),
      queryParameters: {'accountMode': mode.apiValue},
    );
    final contracts = {for (final item in response.data) item.id: item};
    // A long-lived open contract must not vanish behind the recent-history limit.
    String? cursor;
    do {
      final page =
          await _client.get('/timed-contracts', _object, queryParameters: {
        'accountMode': mode.apiValue,
        'result': 'PENDING',
        'limit': 100,
        if (cursor != null) 'cursor': cursor,
      });
      for (final item
          in requireList(page.data['items'], TimedContract.fromJson)) {
        contracts[item.id] = item;
      }
      final next = page.data['nextCursor'] as String?;
      if (next == cursor) break;
      cursor = next;
    } while (cursor != null);
    return contracts.values.toList()
      ..sort((a, b) => b.entryTimestamp.compareTo(a.entryTimestamp));
  }

  Future<String> profitFeeRate() async {
    final response = await _client.get('/timed-contracts/terms',
        (value) => requireString(_object(value), 'profitFeeRate'));
    return response.data;
  }
}

JsonObject _object(dynamic value) {
  if (value is! Map) throw const FormatException('Expected JSON object');
  return Map<String, dynamic>.from(value);
}
