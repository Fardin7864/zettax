import 'package:primevest_mobile/core/api/api_contract.dart';
import 'package:primevest_mobile/core/api/primevest_api_client.dart';
import 'package:primevest_mobile/core/funding/funding_models.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:primevest_mobile/core/trading/pending_contract_store.dart';

// The image picker may re-encode a PNG to JPEG but keep the original name.
String screenshotImageType(Uint8List bytes) {
  const pngSignature = [137, 80, 78, 71, 13, 10, 26, 10];
  if (bytes.length >= pngSignature.length &&
      List.generate(pngSignature.length, (i) => bytes[i] == pngSignature[i])
          .every((matches) => matches)) {
    return 'png';
  }
  if (bytes.length >= 3 &&
      bytes[0] == 255 &&
      bytes[1] == 216 &&
      bytes[2] == 255) {
    return 'jpeg';
  }
  throw const ApiFailure(
    code: 'EVIDENCE_INVALID',
    message: 'Choose a PNG or JPEG screenshot.',
    requestId: '',
  );
}

class FundingRepository {
  FundingRepository(this._client,
      {this.userId = 'test', PendingContractStore? pendingStore})
      : _pending = pendingStore ?? MemoryPendingContractStore();
  final PrimeVestApiClient _client;
  final String userId;
  final PendingContractStore _pending;
  bool _busy = false;
  bool _preparing = false;
  String get _key => 'funding:$userId';
  Future<JsonObject?> pending() async {
    final value = await _pending.read(_key);
    return value == null ? null : _object(jsonDecode(value));
  }

  Future<void> retryPending() async {
    final command = await pending();
    if (command == null) return;
    await _send(command);
  }

  Future<void> _send(JsonObject command) async {
    if (_busy) {
      throw const ApiFailure(
          code: 'FUNDING_BUSY',
          message: 'Wait for your previous request.',
          requestId: '');
    }
    _busy = true;
    try {
      await _client.post(
          command['path'] as String, command['body'], (_) => true,
          idempotencyKey: command['key'] as String,
          receiveTimeout: const Duration(seconds: 60));
      await _pending.clear(_key);
    } on ApiFailure catch (error) {
      if (error.code == 'CONVERSION_RATE_CHANGED' ||
          (command['uncertain'] != true &&
              (error.statusCode == 400 || error.statusCode == 403))) {
        await _pending.clear(_key);
      } else {
        await _pending.write(_key, jsonEncode({...command, 'uncertain': true}));
      }
      rethrow;
    } finally {
      _busy = false;
    }
  }

  Future<void> _submit(String path, JsonObject body) async {
    if (_preparing) {
      throw const ApiFailure(
          code: 'FUNDING_BUSY',
          message: 'Wait for your previous request.',
          requestId: '');
    }
    _preparing = true;
    try {
      if (await pending() != null) {
        throw const ApiFailure(
            code: 'FUNDING_RECOVERY_REQUIRED',
            message: 'Resolve your previous funding request first.',
            requestId: '');
      }
      final command = {
        'path': path,
        'body': body,
        'key': 'funding:mobile:${DateTime.now().microsecondsSinceEpoch}'
      };
      await _pending.write(_key, jsonEncode(command));
      await _send(command);
    } finally {
      _preparing = false;
    }
  }

  String _mobile(String value) => value.startsWith('01') ? '+88$value' : value;
  Future<String> uploadEvidence(Uint8List bytes, String filename) async {
    if (bytes.length > 5 * 1024 * 1024) {
      throw const ApiFailure(
          code: 'EVIDENCE_TOO_LARGE',
          message: 'Choose an image smaller than 5 MB.',
          requestId: '');
    }
    final type = screenshotImageType(bytes);
    final png = type == 'png';
    final form = FormData.fromMap({
      'purpose': 'DEPOSIT',
      'file': MultipartFile.fromBytes(bytes,
          filename: png ? 'receipt.png' : 'receipt.jpg',
          contentType: DioMediaType('image', png ? 'png' : 'jpeg'))
    });
    final response =
        await _client.upload('/evidence', form, (value) => _object(value));
    return requireString(response.data, 'objectKey');
  }

  Future<void> createDeposit(
          {required String methodId,
          required String amount,
          String? expectedConversionRate,
          required String senderMobile,
          required String transactionId,
          String? evidenceObjectKey}) =>
      _submit('/deposits', {
        'paymentMethodId': methodId,
        'amount': amount,
        if (expectedConversionRate != null)
          'expectedConversionRate': expectedConversionRate,
        'senderMobile': _mobile(senderMobile),
        'providerTransactionId': transactionId,
        if (evidenceObjectKey != null) 'evidenceObjectKey': evidenceObjectKey
      });
  Future<List<JsonObject>> history(String path) async {
    final response =
        await _client.get(path, (value) => requireList(value, _object));
    return response.data;
  }

  Future<FundingMethods> depositMethods() =>
      _methods('/deposits/payment-methods');

  Future<FundingMethods> withdrawalMethods() =>
      _methods('/withdrawals/payment-methods');

  Future<FundingMethods> _methods(String path) async {
    final response = await _client.get(
      path,
      (value) => FundingMethods.fromJson(_object(value)),
    );
    return response.data;
  }

  Future<void> createWithdrawal({
    required String methodId,
    required String amount,
    String? expectedConversionRate,
    required String receiverMobile,
    required String verificationMethod,
    required String verificationCode,
  }) async {
    await _submit(
      '/withdrawals',
      {
        'paymentMethodId': methodId,
        'amount': amount,
        if (expectedConversionRate != null)
          'expectedConversionRate': expectedConversionRate,
        'receiverMobile': _mobile(receiverMobile),
        'verificationMethod': verificationMethod,
        'verificationCode': verificationCode,
      },
    );
  }
}

JsonObject _object(dynamic value) {
  if (value is! Map) throw const FormatException('Expected JSON object');
  return Map<String, dynamic>.from(value);
}
