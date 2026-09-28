import 'package:primevest_mobile/core/account/account_models.dart';
import 'package:primevest_mobile/core/api/api_contract.dart';
import 'package:primevest_mobile/core/api/primevest_api_client.dart';

class AccountRepository {
  AccountRepository(this._client);
  final PrimeVestApiClient _client;
  String? _demoResetKey;
  bool _resetting = false;

  Future<JsonObject> resetDemo(String idempotencyKey) async {
    if (_resetting) {
      throw const ApiFailure(
          code: 'RESET_BUSY',
          message: 'Demo reset is already in progress.',
          requestId: '');
    }
    _resetting = true;
    _demoResetKey ??= idempotencyKey;
    try {
      final response = await _client.post(
          '/accounts/demo/reset', const {}, _object,
          idempotencyKey: _demoResetKey);
      _demoResetKey = null;
      return response.data;
    } on ApiFailure catch (error) {
      if (error.statusCode != null &&
          error.statusCode! >= 400 &&
          error.statusCode! < 500) {
        _demoResetKey = null;
      }
      rethrow;
    } finally {
      _resetting = false;
    }
  }

  Future<PublicSystemConfig> systemConfig() async {
    final response = await _client.get(
      '/system/config',
      (value) => PublicSystemConfig.fromJson(_object(value)),
      authenticated: false,
    );
    return response.data;
  }

  Future<CurrentUser> currentUser() async {
    final response = await _client.get(
      '/users/me',
      (value) => CurrentUser.fromJson(_object(value)),
    );
    return response.data;
  }

  Future<List<AccountSummary>> accounts() async {
    final response = await _client.get(
      '/accounts',
      (value) => requireList(value, AccountSummary.fromJson),
    );
    return response.data;
  }
}

JsonObject _object(dynamic value) {
  if (value is! Map) throw const FormatException('Expected JSON object');
  return Map<String, dynamic>.from(value);
}
