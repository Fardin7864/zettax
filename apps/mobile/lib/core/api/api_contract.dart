typedef JsonObject = Map<String, dynamic>;

class ApiMeta {
  const ApiMeta({required this.requestId, required this.timestamp});

  factory ApiMeta.fromJson(JsonObject json) => ApiMeta(
        requestId: requireString(json, 'requestId'),
        timestamp: requireDateTime(json, 'timestamp'),
      );

  final String requestId;
  final DateTime timestamp;
}

class ApiEnvelope<T> {
  const ApiEnvelope({required this.data, required this.meta});

  factory ApiEnvelope.fromJson(
    JsonObject json,
    T Function(dynamic value) decode,
  ) =>
      ApiEnvelope(
        data: decode(json['data']),
        meta: ApiMeta.fromJson(requireObject(json, 'meta')),
      );

  final T data;
  final ApiMeta meta;
}

class ApiFailure implements Exception {
  const ApiFailure({
    required this.code,
    required this.message,
    required this.requestId,
    this.details,
    this.statusCode,
  });

  factory ApiFailure.fromJson(JsonObject json, {int? statusCode}) => ApiFailure(
        code: json['code'] is String ? json['code'] as String : 'NETWORK_ERROR',
        message: json['message'] is String
            ? json['message'] as String
            : 'The request could not be completed.',
        requestId:
            json['requestId'] is String ? json['requestId'] as String : '',
        details: json['details'] is Map
            ? Map<String, dynamic>.from(json['details'] as Map)
            : null,
        statusCode: statusCode,
      );

  final String code;
  final String message;
  final String requestId;
  final JsonObject? details;
  final int? statusCode;

  @override
  String toString() => '$code: $message';
}

JsonObject requireObject(JsonObject json, String key) {
  final value = json[key];
  if (value is! Map) throw FormatException('Missing object $key');
  return Map<String, dynamic>.from(value);
}

String requireString(JsonObject json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Missing string $key');
  }
  return value;
}

DateTime requireDateTime(JsonObject json, String key) {
  final value = DateTime.tryParse(requireString(json, key));
  if (value == null) throw FormatException('Invalid timestamp $key');
  return value.toUtc();
}

List<T> requireList<T>(dynamic value, T Function(JsonObject) decode) {
  if (value is! List) throw const FormatException('Expected a list');
  return value.map((item) {
    if (item is! Map) throw const FormatException('Invalid list item');
    return decode(Map<String, dynamic>.from(item));
  }).toList(growable: false);
}
