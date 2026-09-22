import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:primevest_mobile/app/brand_logo.dart';
import 'package:primevest_mobile/core/app_providers.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});
  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 550))
      ..forward();
    Future<void>.delayed(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      final phase = ref.read(sessionProvider).phase;
      if (phase == SessionPhase.bootstrapping) {
        Future<void>.delayed(const Duration(milliseconds: 300), _leaveSplash);
      } else {
        _leaveSplash();
      }
    });
  }

  void _leaveSplash() {
    if (!mounted) return;
    context.go(ref.read(sessionProvider).phase == SessionPhase.authenticated
        ? '/home'
        : '/welcome');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
            child: FadeTransition(
                opacity: _controller, child: const ZettaxWordmark(width: 240))),
      );
}
