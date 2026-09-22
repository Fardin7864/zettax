import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

class NativeGoogleSignIn {
  final GoogleSignIn _signIn = GoogleSignIn.instance;
  bool _initialized = false;

  Future<String?> getIdToken() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      throw const NativeGoogleSignInFailure(
        'Google sign-in is available in the Android and iOS apps.',
      );
    }
    const serverClientId = String.fromEnvironment(
      'GOOGLE_WEB_CLIENT_ID',
      defaultValue:
          '938817876407-ennda3vg5g7vqdv8usfmv44is2pbnhk1.apps.googleusercontent.com',
    );
    if (serverClientId.isEmpty) {
      throw const NativeGoogleSignInFailure(
        'Google sign-in is not configured for this app build.',
      );
    }
    if (!_initialized) {
      await _signIn.initialize(serverClientId: serverClientId);
      _initialized = true;
    }
    if (!_signIn.supportsAuthenticate()) {
      throw const NativeGoogleSignInFailure(
        'Native Google sign-in is unavailable on this device.',
      );
    }
    try {
      final account = await _signIn.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw const NativeGoogleSignInFailure(
          'Google did not return a secure identity token.',
        );
      }
      return idToken;
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        throw const NativeGoogleSignInFailure(
          'Google sign-in did not complete. Check the Android OAuth package '
          'name and SHA-1 configuration, then try again.',
        );
      }
      throw NativeGoogleSignInFailure(
        error.description ?? 'Google sign-in could not be completed.',
      );
    }
  }

  Future<void> signOut() async {
    if (_initialized) await _signIn.signOut();
  }
}

class NativeGoogleSignInFailure implements Exception {
  const NativeGoogleSignInFailure(this.message);
  final String message;

  @override
  String toString() => message;
}
