import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:primevest_mobile/features/predictions/predictions_screen.dart';

void main() {
  testWidgets(
      'prediction card fits narrow screens and large text without overflow',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final q = <String, dynamic>{
      'symbol': 'BTC/USD',
      'creator': 'A member with a longer display name',
      'creatorAvatarUrl': null,
      'condition': 'ABOVE',
      'targetPrice': '125000.25',
      'status': 'SETTLED',
      'outcome': 'YES',
      'expiresAt': '2026-09-28T06:00:00Z',
      'participantCount': 500,
      'yesDemoPool': '999999.25',
      'noDemoPool': '999999.25',
      'demoYesPoolShare': 50
    };
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: MediaQuery(
                    data: const MediaQueryData(
                        textScaler: TextScaler.linear(1.3)),
                    child: PredictionCard(question: q, onTap: () {}))))));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Will BTC/USD'), findsOneWidget);
  });
}
