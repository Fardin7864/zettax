import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:primevest_mobile/core/api/api_contract.dart';
import 'package:primevest_mobile/core/api/primevest_api_client.dart';
import 'package:primevest_mobile/core/funding/funding_repository.dart';
import 'package:primevest_mobile/core/trading/pending_contract_store.dart';
import 'api_client_test.dart' show CallbackAdapter, MemoryTokenStore;

void main() {
  test('upload declares JPEG bytes correctly even with a PNG filename',
      () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test.invalid'));
    dio.httpClientAdapter = CallbackAdapter((options) async {
      final form = options.data as FormData;
      final file = form.files.single.value;
      expect(file.filename, 'receipt.jpg');
      expect(file.contentType.toString(), 'image/jpeg');
      return ResponseBody.fromString(
          jsonEncode({
            'data': {'objectKey': 'deposit/test/image.enc'},
            'meta': {'requestId': 'test', 'timestamp': '2026-09-18T00:00:00Z'},
          }),
          201,
          headers: {
            Headers.contentTypeHeader: ['application/json']
          });
    });
    final repository = FundingRepository(PrimeVestApiClient(
        tokenStore: MemoryTokenStore(), dio: dio, refreshDio: dio));
    expect(
        await repository.uploadEvidence(
            Uint8List.fromList([255, 216, 255, 224]),
            'original-screenshot.png'),
        'deposit/test/image.enc');
  });

  ResponseBody success() => ResponseBody.fromString(
          jsonEncode({
            'data': {},
            'meta': {'requestId': 'test', 'timestamp': '2026-09-12T00:00:00Z'}
          }),
          201,
          headers: {
            Headers.contentTypeHeader: ['application/json']
          });
  test('uncertain funding retries the original amount and key after restart',
      () async {
    final store = MemoryPendingContractStore();
    final requests = <RequestOptions>[];
    final dio = Dio(BaseOptions(baseUrl: 'http://test.invalid'));
    dio.httpClientAdapter = CallbackAdapter((options) async {
      requests.add(options);
      expect(options.receiveTimeout, const Duration(seconds: 60));
      if (requests.length == 1) {
        throw DioException(
            requestOptions: options, type: DioExceptionType.connectionError);
      }
      if (requests.length == 2) {
        return ResponseBody.fromString(
            jsonEncode({
              'code': 'RELEASE_NOT_APPROVED',
              'message': 'Temporarily blocked',
              'requestId': 'test'
            }),
            403,
            headers: {
              Headers.contentTypeHeader: ['application/json']
            });
      }
      return success();
    });
    final client = PrimeVestApiClient(
        tokenStore: MemoryTokenStore(), dio: dio, refreshDio: dio);
    final one =
        FundingRepository(client, userId: 'customer', pendingStore: store);
    await expectLater(
        one.createWithdrawal(
            methodId: 'method',
            amount: '100.00',
            receiverMobile: '01885482244',
            verificationMethod: 'AUTHENTICATOR',
            verificationCode: '123456'),
        throwsA(isA<ApiFailure>()));
    expect(await one.pending(), isNotNull);
    final restarted =
        FundingRepository(client, userId: 'customer', pendingStore: store);
    await expectLater(restarted.retryPending(), throwsA(isA<ApiFailure>()));
    expect(await restarted.pending(), isNotNull);
    await restarted.retryPending();
    expect(requests.length, 3);
    expect(requests[0].headers['Idempotency-Key'],
        requests[1].headers['Idempotency-Key']);
    expect(requests[0].data, requests[1].data);
    expect((requests[1].data as Map)['receiverMobile'], '+8801885482244');
    expect(await restarted.pending(), isNull);
  });
  test('concurrent submissions cannot overwrite the saved request', () async {
    final pending = Completer<ResponseBody>();
    var calls = 0;
    final dio = Dio(BaseOptions(baseUrl: 'http://test.invalid'));
    dio.httpClientAdapter = CallbackAdapter((options) {
      calls++;
      return pending.future;
    });
    final repository = FundingRepository(PrimeVestApiClient(
        tokenStore: MemoryTokenStore(), dio: dio, refreshDio: dio));
    final first = repository.createWithdrawal(
        methodId: 'method',
        amount: '100.00',
        receiverMobile: '01885482244',
        verificationMethod: 'AUTHENTICATOR',
        verificationCode: '123456');
    await expectLater(
        repository.createWithdrawal(
            methodId: 'method',
            amount: '200.00',
            receiverMobile: '01885482244',
            verificationMethod: 'AUTHENTICATOR',
            verificationCode: '123456'),
        throwsA(isA<ApiFailure>()));
    pending.complete(success());
    await first;
    expect(calls, 1);
  });
}
