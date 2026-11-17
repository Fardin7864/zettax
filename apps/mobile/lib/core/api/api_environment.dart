import 'package:flutter/foundation.dart';

class ApiEnvironment {
  const ApiEnvironment._();

  static const baseUrlValue = String.fromEnvironment(
    'PRIMEVEST_API_BASE_URL',
    defaultValue: kReleaseMode
        ? 'https://api.zettax.app/api/v1'
        : 'http://10.0.2.2:3000/api/v1',
  );

  static Uri get baseUri => validate(baseUrlValue, release: kReleaseMode);

  static Uri validate(String value, {required bool release}) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.hasAuthority ||
        !{'https', 'http'}.contains(uri.scheme) ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw StateError('The API address is invalid.');
    }
    if (release &&
        (uri.scheme != 'https' ||
            uri.host != 'api.zettax.app' ||
            uri.port != 443 ||
            uri.path.replaceFirst(RegExp(r'/$'), '') != '/api/v1')) {
      throw StateError('Release builds must use the Zettax HTTPS API.');
    }
    return uri;
  }
}
