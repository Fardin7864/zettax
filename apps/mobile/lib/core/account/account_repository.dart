import 'package:primevest_mobile/core/account/account_models.dart';
import 'package:primevest_mobile/core/api/api_contract.dart';
import 'package:primevest_mobile/core/api/primevest_api_client.dart';

class AccountRepository {
  const AccountRepository(this._client);
  final PrimeVestApiClient _client;

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
