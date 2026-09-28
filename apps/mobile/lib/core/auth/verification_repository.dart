import 'package:primevest_mobile/core/api/api_contract.dart';
import 'package:primevest_mobile/core/api/primevest_api_client.dart';

class VerificationStatus {
  const VerificationStatus(
      {required this.emailEnabled,
      required this.authenticatorEnabled,
      required this.emailAvailable,
      required this.authenticatorAvailable,
      this.email});
  final bool emailEnabled,
      authenticatorEnabled,
      emailAvailable,
      authenticatorAvailable;
  final String? email;
  bool get enabled => emailEnabled || authenticatorEnabled;
  factory VerificationStatus.fromJson(JsonObject json) => VerificationStatus(
        emailEnabled: json['emailEnabled'] == true,
        authenticatorEnabled: json['authenticatorEnabled'] == true,
        emailAvailable: json['emailAvailable'] == true,
        authenticatorAvailable: json['authenticatorAvailable'] == true,
        email: json['email'] as String?,
      );
}

class VerificationRepository {
  const VerificationRepository(this.client);
  final PrimeVestApiClient client;
  Future<VerificationStatus> status() async => (await client.get(
          '/verification/status',
          (value) => VerificationStatus.fromJson(
              Map<String, dynamic>.from(value as Map))))
      .data;
  Future<JsonObject> command(String path, [String? code]) async =>
      (await client.post(
              '/verification/$path',
              {if (code != null) 'code': code},
              (value) => Map<String, dynamic>.from(value as Map)))
          .data;
}
