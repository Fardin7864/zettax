import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:primevest_mobile/core/api/api_contract.dart';
import 'package:primevest_mobile/core/funding/funding_repository.dart';

void main() {
  test('detects actual PNG and JPEG bytes independently of filenames', () {
    expect(
        screenshotImageType(
            Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10])),
        'png');
    expect(
        screenshotImageType(Uint8List.fromList([255, 216, 255, 224])), 'jpeg');
  });
  test('rejects unsupported or truncated images before upload', () {
    for (final bytes in [
      <int>[],
      [137, 80],
      [71, 73, 70],
      [255, 216]
    ]) {
      expect(() => screenshotImageType(Uint8List.fromList(bytes)),
          throwsA(isA<ApiFailure>()));
    }
  });
}
