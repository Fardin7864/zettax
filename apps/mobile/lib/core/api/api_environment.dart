import 'package:flutter/foundation.dart';

class ApiEnvironment {
  const ApiEnvironment._();

  static const baseUrlValue = String.fromEnvironment(
    'PRIMEVEST_API_BASE_URL',
    defaultValue: kReleaseMode
        ? 'https://api.zettax.app/api/v1'
        : 'http://10.0.2.2:3000/api/v1',
  );

  static Uri get baseUri {
    final uri = Uri.parse(baseUrlValue);
    if (!uri.hasScheme || !uri.hasAuthority) {
      throw StateError('PRIMEVEST_API_BASE_URL must be an absolute URL');
    }
    return uri;
  }
}
