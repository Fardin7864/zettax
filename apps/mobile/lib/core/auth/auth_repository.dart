import 'package:primevest_mobile/core/api/api_contract.dart';
import 'package:primevest_mobile/core/api/primevest_api_client.dart';
import 'package:primevest_mobile/core/auth/auth_models.dart';
import 'package:primevest_mobile/core/auth/token_store.dart';

class AuthRepository {
  const AuthRepository({
    required PrimeVestApiClient client,
    required TokenStore tokenStore,
  })  : _client = client,
        _tokenStore = tokenStore;

  final PrimeVestApiClient _client;
  final TokenStore _tokenStore;

  Future<AuthResult> login(LoginCommand command) async {
    final device = await _tokenStore.deviceMetadata();
    final result = await _client.post(
      '/auth/login',
      {
        'identifier': command.identifier.trim(),
        'password': command.password,
        ...device.toJson(),
      },
      (value) => AuthResult.fromJson(_object(value)),
      authenticated: false,
    );
    await _tokenStore.writeTokens(result.data.tokens);
    return result.data;
  }

  Future<AuthResult> register(RegisterCommand command) async {
    final device = await _tokenStore.deviceMetadata();
    final result = await _client.post(
      '/auth/register',
      {
        'email': command.email.trim().toLowerCase(),
        'password': command.password,
        ...device.toJson(),
      },
      (value) => AuthResult.fromJson(_object(value)),
      authenticated: false,
    );
    await _tokenStore.writeTokens(result.data.tokens);
    return result.data;
  }

  Future<AuthResult> google(String idToken) async {
    final device = await _tokenStore.deviceMetadata();
    final result = await _client.post(
      '/auth/google',
      {'idToken': idToken, ...device.toJson()},
      (value) => AuthResult.fromJson(_object(value)),
      authenticated: false,
    );
    await _tokenStore.writeTokens(result.data.tokens);
    return result.data;
  }

  Future<AuthResult?> restore() async {
    try {
      if (await _tokenStore.readTokens() == null) return null;
      return await _client.refreshSession();
    } catch (_) {
      try {
        await _tokenStore.clearTokens();
      } catch (_) {
        // A storage failure must fail closed to guest mode.
      }
      return null;
    }
  }

  Future<void> logout() async {
    try {
      await _client.post(
        '/auth/logout',
        null,
        (value) => value,
      );
    } finally {
      await _tokenStore.clearTokens();
    }
  }

  Future<List<JsonObject>> sessions() async {
    final response = await _client.get(
        '/auth/sessions',
        (value) => (value as List)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList());
    return response.data;
  }

  Future<void> revokeSession(String sessionId) async {
    await _client.delete('/auth/sessions/$sessionId', (value) => value);
  }

  Future<void> logoutAll() async {
    await _client.post('/auth/logout-all', null, (value) => value);
    await _tokenStore.clearTokens();
  }

  Future<void> changePassword(
      String currentPassword, String newPassword) async {
    await _client.post(
        '/auth/change-password',
        {
          'currentPassword': currentPassword,
          'newPassword': newPassword,
        },
        (value) => value);
  }
}

JsonObject _object(dynamic value) {
  if (value is! Map) throw const FormatException('Expected JSON object');
  return Map<String, dynamic>.from(value);
}
