import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:primevest_mobile/core/app_providers.dart';
import 'package:primevest_mobile/core/api/primevest_api_client.dart';
import 'package:primevest_mobile/features/community/community_safety.dart';
import 'api_client_test.dart'
    show MemoryTokenStore, CallbackAdapter, testDio, jsonResponse;

void main() {
  testWidgets('community rules are accepted only by explicit consent',
      (tester) async {
    final requests = <String>[];
    final dio = testDio(CallbackAdapter((options) async {
      requests.add('${options.method} ${options.path}');
      if (options.path.endsWith('/accept')) {
        expect(options.data, {'version': 'test-version'});
      }
      return jsonResponse({
        'data': {
          'accepted': false,
          'version': 'test-version',
          'title': 'Community rules',
          'text': 'Do not request passwords.'
        },
        'meta': {'requestId': 'fixture', 'timestamp': '2026-10-28T00:00:00Z'}
      });
    }));
    addTearDown(() => dio.close(force: true));
    final client = PrimeVestApiClient(
        tokenStore: MemoryTokenStore(), dio: dio, refreshDio: dio);
    bool? accepted;
    await tester.pumpWidget(ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(client)],
        child: MaterialApp(
            home: Consumer(
                builder: (context, ref, _) => Scaffold(
                    body: TextButton(
                        onPressed: () async {
                          accepted = await ensureCommunityRules(context, ref);
                        },
                        child: const Text('Post')))))));
    await tester.tap(find.text('Post'));
    await tester.pumpAndSettle();
    expect(find.text('Do not request passwords.'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(accepted, false);
    expect(requests.where((x) => x.startsWith('POST')), isEmpty);
    await tester.tap(find.text('Post'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Accept and continue'));
    await tester.pumpAndSettle();
    expect(accepted, true);
    expect(requests.where((x) => x.startsWith('POST')).toList(),
        ['POST /community/rules/accept']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'report sends a reason; blocking requires confirmation and refreshes visibility',
      (tester) async {
    final requests = <String>[];
    final bodies = <dynamic>[];
    final dio = testDio(CallbackAdapter((options) async {
      requests.add(options.path);
      bodies.add(options.data);
      return jsonResponse({
        'data': {'status': 'OPEN'},
        'meta': {'requestId': 'fixture', 'timestamp': '2026-10-28T00:00:00Z'}
      });
    }));
    addTearDown(() => dio.close(force: true));
    var reloads = 0;
    final client = PrimeVestApiClient(
        tokenStore: MemoryTokenStore(), dio: dio, refreshDio: dio);
    await tester.pumpWidget(ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(client)],
        child: MaterialApp(
            home: Scaffold(
                body: CommunitySafetyMenu(
                    targetType: 'POST',
                    targetId: 'test-post',
                    onChanged: () => reloads++)))));
    await tester.tap(find.byTooltip('Community safety'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report content'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Requests a bank password');
    await tester.tap(find.text('Send report'));
    await tester.pumpAndSettle();
    expect(requests, ['/community/reports']);
    expect(bodies.single, {
      'targetType': 'POST',
      'targetId': 'test-post',
      'reason': 'Requests a bank password'
    });
    await tester.tap(find.byTooltip('Community safety'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Block user'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(requests.length, 1);
    await tester.tap(find.byTooltip('Community safety'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Block user'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Block user'));
    await tester.pumpAndSettle();
    expect(requests.last, '/community/blocks');
    expect(reloads, 1);
    await tester.pump(const Duration(seconds: 5));
    expect(tester.takeException(), isNull);
  });
}
