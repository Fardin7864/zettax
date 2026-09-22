import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:primevest_mobile/app/top_notification.dart';

void main() {
  testWidgets('notifications appear at the top and can be dismissed',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        builder: (_, child) => TopNotificationHost(child: child!),
        home: const Scaffold(body: Text('Page'))));
    showTopNotification('Trade started', success: true);
    await tester.pump();
    expect(find.text('Trade started'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Trade started')).dy, lessThan(100));
    expect(find.byType(SnackBar), findsNothing);
    await tester.tap(find.byKey(const ValueKey('dismiss-top-notification')));
    await tester.pump();
    expect(find.text('Trade started'), findsNothing);
  });
}
