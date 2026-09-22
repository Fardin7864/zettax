import 'package:flutter_test/flutter_test.dart';
import 'package:primevest_mobile/app/app_update_host.dart';

void main() {
  final manifest = <String, dynamic>{
    'versionCode': 3,
    'versionName': '0.2.1',
    'apkUrl': 'https://zettax.app/downloads/zettax-latest.apk',
    'sha256': List.filled(64, 'a').join(),
  };

  test('offers a newer trusted and checksummed APK', () {
    expect(isEligibleZettaxUpdate(manifest, 2), isTrue);
    expect(isEligibleZettaxUpdate(manifest, 3), isFalse);
  });

  test('rejects untrusted download destinations and invalid checksums', () {
    for (final url in [
      'http://zettax.app/downloads/zettax-latest.apk',
      'https://zettax.app.evil.example/downloads/zettax-latest.apk',
      'https://user@zettax.app/downloads/zettax-latest.apk',
      'https://zettax.app:8443/downloads/zettax-latest.apk',
      'https://zettax.app/other/zettax-latest.apk',
    ]) {
      expect(isEligibleZettaxUpdate({...manifest, 'apkUrl': url}, 2), isFalse);
    }
    expect(isEligibleZettaxUpdate({...manifest, 'sha256': 'nope'}, 2), isFalse);
  });
}
