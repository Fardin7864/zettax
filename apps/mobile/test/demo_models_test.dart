import 'package:flutter_test/flutter_test.dart';
import 'package:primevest_mobile/demo/models.dart';
import 'package:primevest_mobile/demo/providers.dart';

void main() {
  test('decodes typed mock instruments', () {
    final assets = decodeAssets('''
      [{
        "id": "btc-usd",
        "symbol": "BTC/USD",
        "name": "Bitcoin",
        "assetClass": "Crypto",
        "price": 64000.25,
        "changePercent": 1.5,
        "precision": 2
      }]
    ''');

    expect(assets, hasLength(1));
    expect(assets.single.symbol, 'BTC/USD');
    expect(assets.single.assetClass, 'Crypto');
    expect(assets.single.price, 64000.25);
  });

  test('formats BDT from integer paisa without floating-point storage', () {
    expect(bdt(10000000), '৳100,000.00');
    expect(bdt(-125050), '-৳1,250.50');
  });
}
