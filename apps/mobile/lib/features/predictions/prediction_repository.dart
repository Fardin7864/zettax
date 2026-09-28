import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:primevest_mobile/core/app_providers.dart';
import 'package:primevest_mobile/core/api/api_contract.dart';
import 'package:primevest_mobile/core/api/primevest_api_client.dart';
import 'package:primevest_mobile/core/trading/pending_contract_store.dart';

typedef PredictionRow = Map<String, dynamic>;
PredictionRow predictionObject(dynamic value) =>
    Map<String, dynamic>.from(value as Map);

final predictionRepositoryProvider = Provider((ref) => PredictionRepository(
    ref.watch(apiClientProvider),
    ref.watch(sessionProvider).user?.id ?? 'guest'));

class PredictionRepository {
  PredictionRepository(this.client, this.userId,
      {PendingContractStore? pendingStore})
      : store = pendingStore ?? const SecurePendingContractStore();
  final PrimeVestApiClient client;
  final String userId;
  final PendingContractStore store;
  bool busy = false;
  String get storageKey => 'prediction:$userId';
  Future<PredictionRow> read(String path,
          {Map<String, dynamic>? query, bool public = false}) async =>
      (await client.get('/prediction/$path', predictionObject,
              queryParameters: query, authenticated: !public))
          .data;
  Future<PredictionRow?> pending() async {
    final raw = await store.read(storageKey);
    return raw == null ? null : predictionObject(jsonDecode(raw));
  }

  Future<void> submit(String path, PredictionRow body) async {
    if (busy) throw StateError('A prediction request is already in progress.');
    busy = true;
    try {
      if (await pending() != null) {
        throw StateError('Retry your previous request before making another.');
      }
      await store.write(
          storageKey,
          jsonEncode({
            'path': path,
            'body': body,
            'key': 'prediction:mobile:${DateTime.now().microsecondsSinceEpoch}'
          }));
      await _send();
    } finally {
      busy = false;
    }
  }

  Future<void> retry() async {
    if (busy) return;
    busy = true;
    try {
      await _send();
    } finally {
      busy = false;
    }
  }

  Future<void> _send() async {
    final command = await pending();
    if (command == null) return;
    try {
      await client.post(
          '/prediction/${command['path']}', command['body'], predictionObject,
          idempotencyKey: command['key'] as String,
          receiveTimeout: const Duration(seconds: 60));
      await store.clear(storageKey);
    } on ApiFailure catch (error) {
      // A timeout or server failure may have committed: retain the exact command/key.
      if ([400, 403, 404, 409, 429].contains(error.statusCode)) {
        await store.clear(storageKey);
      }
      rethrow;
    }
  }

  Future<void> report(String id, String reason) async {
    await client.post('/prediction/questions/$id/report', {'reason': reason},
        predictionObject);
  }
}
