import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:primevest_mobile/core/auth/auth_models.dart';

abstract interface class TokenStore {
  Future<SessionTokens?> readTokens();
  Future<void> writeTokens(SessionTokens tokens);
  Future<void> clearTokens();
  Future<DeviceMetadata> deviceMetadata();
}

class SecureTokenStore implements TokenStore {
  SecureTokenStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _accessKey = 'auth.access_token';
  static const _refreshKey = 'auth.refresh_token';
  static const _expiresKey = 'auth.access_expires_in';
  static const _deviceKey = 'device.fingerprint';

  final FlutterSecureStorage _storage;

  @override
  Future<SessionTokens?> readTokens() async {
    final values = await Future.wait([
      _storage.read(key: _accessKey),
      _storage.read(key: _refreshKey),
      _storage.read(key: _expiresKey),
    ]);
    final expires = int.tryParse(values[2] ?? '');
    if (values[0] == null || values[1] == null || expires == null) return null;
    return SessionTokens(
      accessToken: values[0]!,
      refreshToken: values[1]!,
      accessTokenExpiresIn: expires,
    );
  }

  @override
  Future<void> writeTokens(SessionTokens tokens) => Future.wait([
        _storage.write(key: _accessKey, value: tokens.accessToken),
        _storage.write(key: _refreshKey, value: tokens.refreshToken),
        _storage.write(
          key: _expiresKey,
          value: tokens.accessTokenExpiresIn.toString(),
        ),
      ]).then((_) {});

  @override
  Future<void> clearTokens() => Future.wait([
        _storage.delete(key: _accessKey),
        _storage.delete(key: _refreshKey),
        _storage.delete(key: _expiresKey),
      ]).then((_) {});

  @override
  Future<DeviceMetadata> deviceMetadata() async {
    var fingerprint = await _storage.read(key: _deviceKey);
    if (fingerprint == null) {
      final bytes = List<int>.generate(24, (_) => Random.secure().nextInt(256));
      fingerprint = base64UrlEncode(bytes);
      await _storage.write(key: _deviceKey, value: fingerprint);
    }
    return DeviceMetadata(
      deviceFingerprint: fingerprint,
      deviceName: 'Zettax mobile',
      devicePlatform: defaultTargetPlatform.name,
    );
  }
}
