import 'package:flutter/widgets.dart';

class WebGoogleButton extends StatelessWidget {
  const WebGoogleButton({super.key, required this.onAuthenticated});
  final Future<void> Function(String idToken) onAuthenticated;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
