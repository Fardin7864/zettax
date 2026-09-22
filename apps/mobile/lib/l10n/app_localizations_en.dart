// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Zettax';

  @override
  String get welcomeTitle => 'Learn markets with clarity';

  @override
  String get welcomeBody =>
      'Explore simulated markets and practice trading with virtual funds.';

  @override
  String get tryDemo => 'Try Demo';

  @override
  String get createAccount => 'Create Account';

  @override
  String get login => 'Log in';

  @override
  String get demo => 'DEMO';

  @override
  String get simulatedData => 'Simulated market data';

  @override
  String get home => 'Home';

  @override
  String get markets => 'Markets';

  @override
  String get trade => 'Trade';

  @override
  String get portfolio => 'Portfolio';

  @override
  String get profile => 'Profile';

  @override
  String get availableBalance => 'Available balance';
}
