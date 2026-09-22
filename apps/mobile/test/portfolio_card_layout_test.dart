import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:primevest_mobile/demo/models.dart';
import 'package:primevest_mobile/features/shared/market_widgets.dart';

void main() {
  const asset = MarketAsset(
    id: 'test-asset',
    symbol: 'BTC/USD',
    name: 'Bitcoin',
    assetClass: 'Crypto',
    price: 0,
    changePercent: 0,
    precision: 2,
  );

  for (final scale in [1.0, 1.3, 1.6]) {
    testWidgets('portfolio trade card fits a narrow screen at ${scale}x text',
        (tester) async {
      tester.view.physicalSize = const Size(720, 1440);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 260,
                height: 224,
              child: ActivityCard(
                asset: asset,
                title: 'BTC/USD',
                badge: 'DOWN • PENDING',
                value: 'Returned ৳1000.00',
                positive: true,
                subtitle:
                    'Stake ৳1000.00 • P/L +৳0.00 • Fee ৳0.00 • Updated at expiry',
              ),
            ),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
    });
  }
}
