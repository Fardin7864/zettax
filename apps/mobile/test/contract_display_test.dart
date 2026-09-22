import 'package:flutter_test/flutter_test.dart';
import 'package:primevest_mobile/core/trading/contract_display.dart';

void main() {
  final now = DateTime.utc(2026, 9, 12);
  test('shows long durations without a seconds cap', () {
    expect(contractTimeRemaining(now.add(const Duration(days: 365)), now: now),
        '365d 0h');
    expect(
        contractTimeRemaining(now.add(const Duration(hours: 2, minutes: 3)),
            now: now),
        '2h 3m');
  });
  test('does not settle early or claim a substituted live return', () {
    expect(
        contractTimeRemaining(now.add(const Duration(milliseconds: 1)),
            now: now),
        '00:01');
    expect(contractTimeRemaining(now, now: now), 'Awaiting settlement');
    expect(
        contractTimeRemaining(now.subtract(const Duration(seconds: 10)),
            now: now),
        'Awaiting settlement');
  });
  test('live estimate shows proportional return and net profit or loss', () {
    final profit = estimateContractReturn(
      stake: 1000,
      entryPrice: 100,
      currentPrice: 102,
      up: true,
      profitFeeRate: 0.1,
    );
    expect(profit.returnAmount.toStringAsFixed(2), '1018.00');
    expect(profit.pnl.toStringAsFixed(2), '18.00');

    final loss = estimateContractReturn(
      stake: 1000,
      entryPrice: 100,
      currentPrice: 98,
      up: true,
    );
    expect(loss.returnAmount.toStringAsFixed(2), '980.00');
    expect(loss.pnl.toStringAsFixed(2), '-20.00');
  });
  test('sub-paisa movement is visible without promising a payout', () {
    final estimate = estimateContractReturn(
      stake: 1000,
      entryPrice: 76509.62,
      currentPrice: 76509.61,
      up: false,
    );
    expect(estimate.returnAmount.toStringAsFixed(2), '1000.00');
    expect(estimate.pnl, 0);
    expect(estimate.rawPnl, greaterThan(0));
  });
}
