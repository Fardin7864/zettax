import 'package:flutter_test/flutter_test.dart';
import 'package:primevest_mobile/demo/models.dart';

void main() {
  test('guest returns track price movement instead of a fixed win bonus', () {
    expect(proportionalVirtualReturn(10000, 100, 101, ContractDirection.up),
        10100);
    expect(
        proportionalVirtualReturn(10000, 100, 99, ContractDirection.up), 9900);
    expect(proportionalVirtualReturn(10000, 100, 99, ContractDirection.down),
        10100);
    expect(proportionalVirtualReturn(10000, 100, 101, ContractDirection.down),
        9900);
    expect(proportionalVirtualReturn(10000, 100, 100, ContractDirection.up),
        10000);
  });
  test('virtual returns cannot become negative and invalid prices are rejected',
      () {
    expect(
        proportionalVirtualReturn(10000, 100, 250, ContractDirection.down), 0);
    expect(proportionalVirtualReturn(10000, 100, 0, ContractDirection.up), 0);
    for (final entry in [0.0, -1.0, double.nan, double.infinity]) {
      expect(
          () => proportionalVirtualReturn(
              10000, entry, 100, ContractDirection.up),
          throwsArgumentError);
    }
    for (final expiry in [-1.0, double.nan, double.infinity]) {
      expect(
          () => proportionalVirtualReturn(
              10000, 100, expiry, ContractDirection.up),
          throwsArgumentError);
    }
  });
}
