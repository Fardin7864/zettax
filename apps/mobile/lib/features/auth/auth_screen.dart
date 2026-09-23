import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:primevest_mobile/app/brand_logo.dart';
import 'package:primevest_mobile/app/design_system.dart';
import 'package:primevest_mobile/app/top_notification.dart';
import 'package:primevest_mobile/core/api/api_contract.dart';
import 'package:primevest_mobile/core/app_providers.dart';
import 'package:primevest_mobile/core/auth/auth_models.dart';
import 'package:primevest_mobile/core/auth/native_google_sign_in.dart';
import 'package:primevest_mobile/features/auth/web_google_button_stub.dart'
    if (dart.library.js_interop) 'package:primevest_mobile/features/auth/web_google_button.dart';

enum AuthMode { login, register, forgotPassword }

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key, required this.mode});
  final AuthMode mode;

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final formKey = GlobalKey<FormState>();
  final identifier = TextEditingController();
  final password = TextEditingController();
  bool submitting = false;
  bool obscurePassword = true;

  bool get isRegister => widget.mode == AuthMode.register;
  bool get isForgot => widget.mode == AuthMode.forgotPassword;

  @override
  void dispose() {
    for (final controller in [
      identifier,
      password,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(),
        body: SafeArea(
          top: false,
          child: Form(
            key: formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: ZettaxMark(height: 90),
                ),
                const SizedBox(height: 30),
                Text(
                  isRegister
                      ? 'Create your account'
                      : isForgot
                          ? 'Reset your password'
                          : 'Welcome back',
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isForgot
                      ? 'Password recovery is not exposed by the current server yet. No mock reset message will be presented as real.'
                      : 'Secure authentication uses the Zettax server. You can still skip sign-in and use the isolated guest demo.',
                  style: const TextStyle(
                    color: PrimeVestDesignSystem.textMuted,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 26),
                _field(
                  identifier,
                  isRegister ? 'Email address' : 'Email or mobile',
                  Icons.alternate_email,
                  keyboardType: TextInputType.emailAddress,
                  validator: _required,
                ),
                if (!isForgot) ...[
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: password,
                    obscureText: obscurePassword,
                    autofillHints: isRegister
                        ? const [AutofillHints.newPassword]
                        : const [AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        onPressed: () => setState(
                          () => obscurePassword = !obscurePassword,
                        ),
                        icon: Icon(
                          obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: isRegister ? _strongPassword : _required,
                  ),
                ],
                if (widget.mode == AuthMode.login)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => context.push('/forgot-password'),
                      child: const Text('Forgot password?'),
                    ),
                  )
                else
                  const SizedBox(height: 22),
                FilledButton(
                  onPressed: submitting || isForgot ? null : _submit,
                  child: submitting
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(isRegister
                          ? 'Create account'
                          : isForgot
                              ? 'Unavailable until server support lands'
                              : 'Sign in'),
                ),
                if (!isForgot) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Row(
                      children: [
                        Expanded(child: Divider()),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'or',
                            style: TextStyle(
                              color: PrimeVestDesignSystem.textMuted,
                            ),
                          ),
                        ),
                        Expanded(child: Divider()),
                      ],
                    ),
                  ),
                  if (kIsWeb)
                    WebGoogleButton(onAuthenticated: _completeWebGoogle)
                  else
                    OutlinedButton(
                      onPressed: submitting ? null : _submitGoogle,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(54),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'G',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF4285F4),
                            ),
                          ),
                          SizedBox(width: 12),
                          Text('Continue with Google'),
                        ],
                      ),
                    ),
                ],
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => context.go('/home'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                  ),
                  child: const Text('Skip and use guest demo'),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon, {
    String? hint,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) =>
      TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon),
        ),
        validator: validator,
      );

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'This field is required' : null;

  String? _strongPassword(String? value) {
    final candidate = value ?? '';
    if (candidate.length < 12 ||
        !RegExp(r'[a-z]').hasMatch(candidate) ||
        !RegExp(r'[A-Z]').hasMatch(candidate) ||
        !RegExp(r'\d').hasMatch(candidate) ||
        !RegExp(r'[^A-Za-z\d]').hasMatch(candidate)) {
      return 'Use 12+ characters with upper, lower, number and symbol';
    }
    return null;
  }

  Future<void> _submit() async {
    if (!formKey.currentState!.validate()) return;
    setState(() => submitting = true);
    final controller = ref.read(sessionProvider.notifier);
    final succeeded = isRegister
        ? await controller.register(RegisterCommand(
            email: identifier.text,
            password: password.text,
          ))
        : await controller.login(LoginCommand(
            identifier: identifier.text,
            password: password.text,
          ));
    if (!mounted) return;
    setState(() => submitting = false);
    if (succeeded) {
      context.go('/home');
      return;
    }
    _showFailure();
  }

  Future<void> _submitGoogle() async {
    setState(() => submitting = true);
    final succeeded = await ref.read(sessionProvider.notifier).google();
    if (!mounted) return;
    setState(() => submitting = false);
    if (succeeded) {
      context.go('/home');
      return;
    }
    final failure = ref.read(sessionProvider).failure;
    if (failure != null) _showFailure();
  }

  Future<void> _completeWebGoogle(String idToken) async {
    if (!mounted || submitting) return;
    setState(() => submitting = true);
    final succeeded =
        await ref.read(sessionProvider.notifier).googleWithIdToken(idToken);
    if (!mounted) return;
    setState(() => submitting = false);
    if (succeeded) {
      context.go('/home');
    } else {
      _showFailure();
    }
  }

  void _showFailure() {
    final failure = ref.read(sessionProvider).failure;
    final message = switch (failure) {
      ApiFailure failure => failure.message,
      NativeGoogleSignInFailure failure => failure.message,
      _ => 'Unable to reach Zettax. Check the server and try again.',
    };
    showTopNotification(message, success: false);
  }
}
