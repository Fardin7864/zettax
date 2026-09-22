import 'package:flutter/services.dart';
import 'package:primevest_mobile/demo/models.dart';

/// Offline stand-in for the future PrimeVest REST API.
///
/// Screens depend on this boundary instead of reading bundled JSON directly,
/// so the real Dio-backed implementation can replace it without changing UI.
class MockPrimeVestApi {
  const MockPrimeVestApi();

  static const providerName = 'Zettax Mock Market v1';

  Future<List<MarketAsset>> fetchInstruments() async {
    await Future<void>.delayed(const Duration(milliseconds: 280));
    final source = await rootBundle.loadString('assets/mock/instruments.json');
    return decodeAssets(source);
  }

  /// Represents the authoritative clock returned by the mock API.
  DateTime serverNow() => DateTime.now().toUtc();
}
