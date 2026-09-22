import 'package:flutter_test/flutter_test.dart';
import 'package:primevest_mobile/features/funding/funding_brand.dart';

void main() {
  test('each funding service has its own logo and accent', () {
    final bkash = FundingBrand.forType('BKASH')!;
    final nagad = FundingBrand.forType('NAGAD')!;
    final rocket = FundingBrand.forType('ROCKET')!;
    expect([bkash.name, nagad.name, rocket.name], ['bKash', 'Nagad', 'Rocket']);
    expect({bkash.color, nagad.color, rocket.color}, hasLength(3));
    expect(
        [bkash.imageUrl, nagad.imageUrl, rocket.imageUrl]
            .every((url) => url.startsWith('https://')),
        isTrue);
    expect(FundingBrand.forType('manual'), isNull);
  });
}
