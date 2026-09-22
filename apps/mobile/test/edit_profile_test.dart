import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:primevest_mobile/app/top_notification.dart';
import 'package:primevest_mobile/core/account/account_models.dart';
import 'package:primevest_mobile/core/api/api_contract.dart';
import 'package:primevest_mobile/core/api/primevest_api_client.dart';
import 'package:primevest_mobile/core/app_providers.dart';
import 'package:primevest_mobile/features/profile/edit_profile_screen.dart';
import 'api_client_test.dart' show MemoryTokenStore;

class ProfileClient extends PrimeVestApiClient {
  ProfileClient() : super(tokenStore: MemoryTokenStore());
  String? path;
  Object? body;
  @override
  Future<ApiEnvelope<T>> post<T>(
    String path,
    Object? body,
    T Function(dynamic) decode, {
    bool authenticated = true,
    String? idempotencyKey,
    Duration? receiveTimeout,
  }) async {
    this.path = path;
    this.body = body;
    return ApiEnvelope(
        data: decode({}),
        meta: ApiMeta(requestId: 'test', timestamp: DateTime.now()));
  }
}

void main() {
  test('profile dates do not shift and optional address fields can be empty',
      () {
    final profile = UserProfile.fromJson({
      'fullName': 'Investor',
      'dateOfBirth': '2000-01-01T00:00:00.000Z',
      'currentAddress': '',
      'district': '',
      'country': 'Bangladesh',
    });
    expect(profile.dateOfBirth.year, 2000);
    expect(profile.dateOfBirth.month, 1);
    expect(profile.dateOfBirth.day, 1);
    expect(profile.currentAddress, '');
    expect(profile.district, '');
  });
  testWidgets(
      'profile editor saves changed details to the authenticated profile endpoint',
      (tester) async {
    final client = ProfileClient();
    final user = CurrentUser.fromJson({
      'id': 'user-1',
      'email': 'test@example.com',
      'createdAt': '2026-09-18T00:00:00Z',
      'profile': {
        'fullName': 'Original',
        'dateOfBirth': '2000-01-01',
        'currentAddress': 'Address',
        'district': 'Dhaka',
        'country': 'Bangladesh'
      },
    });
    await tester.pumpWidget(ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(client)],
        child: MaterialApp(
            builder: (_, child) => TopNotificationHost(child: child!),
            home: Scaffold(
                body: Builder(
                    builder: (context) => TextButton(
                        onPressed: () {
                          Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                  builder: (_) =>
                                      EditProfileScreen(user: user)));
                        },
                        child: const Text('Open editor')))))));
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextFormField).first, 'Updated Investor');
    await tester.scrollUntilVisible(find.text('Save profile'), 250,
        scrollable: find
            .descendant(
                of: find.byType(ListView), matching: find.byType(Scrollable))
            .first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save profile'));
    await tester.pumpAndSettle();
    expect(client.path, '/users/me/profile');
    expect(client.body, containsPair('fullName', 'Updated Investor'));
    expect(client.body, containsPair('dateOfBirth', '2000-01-01'));
    expect(find.text('Profile updated.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('dismiss-top-notification')));
    await tester.pump();
  });
}
