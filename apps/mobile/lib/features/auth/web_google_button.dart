import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_web/web_only.dart' as web;

class WebGoogleButton extends StatefulWidget {
  const WebGoogleButton({super.key, required this.onAuthenticated});
  final Future<void> Function(String idToken) onAuthenticated;

  @override
  State<WebGoogleButton> createState() => _WebGoogleButtonState();
}

class _WebGoogleButtonState extends State<WebGoogleButton> {
  StreamSubscription<GoogleSignInAuthenticationEvent>? _events;
  String? _error;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await GoogleSignIn.instance.initialize();
      if (!mounted) return;
      _events = GoogleSignIn.instance.authenticationEvents.listen((event) {
        if (event is GoogleSignInAuthenticationEventSignIn) {
          final idToken = event.user.authentication.idToken;
          if (idToken != null && idToken.isNotEmpty) {
            widget.onAuthenticated(idToken);
          }
        }
      }, onError: (Object error) {
        if (mounted) {
          setState(() => _error = 'Google sign-in failed. Try again.');
        }
      });
      setState(() => _ready = true);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Google sign-in is unavailable.');
      }
    }
  }

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        if (_ready) Center(child: web.renderButton()),
        if (!_ready && _error == null)
          const Center(child: CircularProgressIndicator()),
        if (_error != null) Text(_error!),
      ]);
}
