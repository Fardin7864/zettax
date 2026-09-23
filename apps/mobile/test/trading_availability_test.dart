import 'package:flutter_test/flutter_test.dart';
import 'package:primevest_mobile/core/account/account_models.dart';

void main() {
  test('REAL virtual trading follows the server flag, not a DEMO-only gate',
      () {
    final config = PublicSystemConfig.fromJson({
      'complianceMode': 'SANDBOX',
      'demo': {'initialBalanceUsd': '1000.00'},
      'real': {
        'trading': true,
        'deposits': true,
        'withdrawals': true,
        'fundsKind': 'VIRTUAL'
      },
      'serverTime': '2026-09-18T00:00:00Z',
    });
    expect(config.tradingAvailableFor(AccountMode.real), isTrue);
    expect(config.tradingAvailableFor(AccountMode.demo), isTrue);
    expect(config.usesVirtualFunds, isTrue);
    expect(PublicSystemConfig.failClosed.tradingAvailableFor(AccountMode.real),
        isFalse);
  });
}
