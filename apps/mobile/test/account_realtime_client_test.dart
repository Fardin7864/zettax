import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:primevest_mobile/core/account/account_realtime_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('account event cursors are isolated per signed-in user', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final first = SecureAccountEventCursorStore(userId: 'first');
    final second = SecureAccountEventCursorStore(userId: 'second');
    await first.write(42);
    expect(await first.read(), 42);
    expect(await second.read(), isNull);
    await second.write(7);
    expect(await first.read(), 42);
    expect(await second.read(), 7);
  });
  test('parses durable account events with decimal-string sequence', () {
    final event = AccountRealtimeEvent.fromJson({
      'schemaVersion': 1,
      'sequence': '42',
      'type': 'position.closed',
      'payload': {'realizedPnl': '-1.25'},
    });
    expect(event.sequence, 42);
    expect(event.type, 'position.closed');
    expect(event.payload['realizedPnl'], '-1.25');
  });

  test('rejects malformed or unsafe account events', () {
    expect(
      () => AccountRealtimeEvent.fromJson({
        'schemaVersion': 2,
        'sequence': '1',
        'type': 'order.filled',
        'payload': <String, dynamic>{},
      }),
      throwsFormatException,
    );
    expect(
      () => AccountRealtimeEvent.fromJson({
        'schemaVersion': 1,
        'sequence': '-1',
        'type': 'order.filled',
        'payload': <String, dynamic>{},
      }),
      throwsFormatException,
    );
  });
}
