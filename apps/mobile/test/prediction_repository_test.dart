import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:primevest_mobile/core/api/api_contract.dart';
import 'package:primevest_mobile/core/api/primevest_api_client.dart';
import 'package:primevest_mobile/core/trading/pending_contract_store.dart';
import 'package:primevest_mobile/features/predictions/prediction_repository.dart';
import 'api_client_test.dart' show CallbackAdapter, MemoryTokenStore;

void main() {
  test(
      'prediction retry preserves the exact request after network loss and restart',
      () async {
    final store = MemoryPendingContractStore(), requests = <RequestOptions>[];
    final dio = Dio(BaseOptions(baseUrl: 'http://test.invalid'));
    dio.httpClientAdapter = CallbackAdapter((options) async {
      requests.add(options);
      if (requests.length == 1) {
        throw DioException(
            requestOptions: options, type: DioExceptionType.connectionError);
      }
      return ResponseBody.fromString(
          jsonEncode({
            'data': {'id': 'position'},
            'meta': {'requestId': 'test', 'timestamp': '2026-09-28T00:00:00Z'}
          }),
          201,
          headers: {
            Headers.contentTypeHeader: ['application/json']
          });
    });
    final client = PrimeVestApiClient(
        tokenStore: MemoryTokenStore(), dio: dio, refreshDio: dio);
    final repository =
        PredictionRepository(client, 'user', pendingStore: store);
    await expectLater(
        repository.submit('questions/question/positions',
            {'side': 'YES', 'stake': '10.00', 'accountMode': 'DEMO'}),
        throwsA(isA<ApiFailure>()));
    expect(await repository.pending(), isNotNull);
    await expectLater(
        repository.submit('questions/other/positions', {}), throwsStateError);
    final restarted = PredictionRepository(client, 'user', pendingStore: store);
    await restarted.retry();
    expect(requests.length, 2);
    expect(requests[0].headers['Idempotency-Key'],
        requests[1].headers['Idempotency-Key']);
    expect(requests[0].data, requests[1].data);
    expect(await restarted.pending(), isNull);
  });
}
