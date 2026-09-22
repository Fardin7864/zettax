import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final appLocaleProvider = StateNotifierProvider<AppLocaleController, Locale?>(
    (ref) => AppLocaleController());

class AppLocaleController extends StateNotifier<Locale?> {
  AppLocaleController() : super(null) {
    _load();
  }

  static const _storage = FlutterSecureStorage();
  static const _key = 'primevest.interface_language';

  Future<void> _load() async {
    try {
      final code = await _storage.read(key: _key);
      if (mounted && (code == 'en' || code == 'bn')) state = Locale(code!);
    } catch (_) {
      // Device locale remains active when local preference storage fails.
    }
  }

  Future<void> select(String code) async {
    if (code != 'en' && code != 'bn') return;
    await _storage.write(key: _key, value: code);
    state = Locale(code);
  }
}

class LanguageScreen extends ConsumerWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(appLocaleProvider)?.languageCode ??
        Localizations.localeOf(context).languageCode;
    return Scaffold(
      appBar: AppBar(title: const Text('Language / ভাষা')),
      body: ListView(children: [
        const Padding(
          padding: EdgeInsets.all(20),
          child: Text(
              'Choose your interface language. Your selection is saved on this device.'),
        ),
        RadioGroup<String>(
          groupValue: selected,
          onChanged: (code) {
            if (code != null) ref.read(appLocaleProvider.notifier).select(code);
          },
          child: const Column(children: [
            RadioListTile<String>(title: Text('English'), value: 'en'),
            RadioListTile<String>(title: Text('বাংলা'), value: 'bn'),
          ]),
        ),
        const Padding(
          padding: EdgeInsets.all(20),
          child: Text(
              'Some trading and account labels are still available in English while translations are completed.'),
        ),
      ]),
    );
  }
}
