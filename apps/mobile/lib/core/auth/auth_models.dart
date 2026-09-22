import 'package:primevest_mobile/core/api/api_contract.dart';

class AuthUser {
  const AuthUser({required this.id, required this.email, this.phone});

  factory AuthUser.fromJson(JsonObject json) => AuthUser(
        id: requireString(json, 'id'),
        email: requireString(json, 'email'),
        phone: json['phone'] as String?,
      );

  final String id;
  final String email;
  final String? phone;
}

class SessionTokens {
  const SessionTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.accessTokenExpiresIn,
  });

  factory SessionTokens.fromJson(JsonObject json) => SessionTokens(
        accessToken: requireString(json, 'accessToken'),
        refreshToken: requireString(json, 'refreshToken'),
        accessTokenExpiresIn: json['accessTokenExpiresIn'] as int,
      );

  final String accessToken;
  final String refreshToken;
  final int accessTokenExpiresIn;
}

class AuthResult {
  const AuthResult({required this.tokens, required this.user});

  factory AuthResult.fromJson(JsonObject json) => AuthResult(
        tokens: SessionTokens.fromJson(json),
        user: AuthUser.fromJson(requireObject(json, 'user')),
      );

  final SessionTokens tokens;
  final AuthUser user;
}

class DeviceMetadata {
  const DeviceMetadata({
    required this.deviceFingerprint,
    required this.deviceName,
    required this.devicePlatform,
  });

  final String deviceFingerprint;
  final String deviceName;
  final String devicePlatform;

  JsonObject toJson() => {
        'deviceFingerprint': deviceFingerprint,
        'deviceName': deviceName,
        'devicePlatform': devicePlatform,
      };
}

class LoginCommand {
  const LoginCommand({required this.identifier, required this.password});
  final String identifier;
  final String password;
}

class RegisterCommand {
  const RegisterCommand({
    required this.email,
    required this.password,
  });

  final String email;
  final String password;
}
