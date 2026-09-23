import 'package:primevest_mobile/core/api/api_contract.dart';

class FundingMethod {
  const FundingMethod({
    required this.id,
    required this.type,
    required this.displayName,
    required this.accountNumber,
    required this.accountType,
    required this.instructions,
    required this.minimum,
    required this.maximum,
  });

  factory FundingMethod.fromJson(JsonObject json) => FundingMethod(
        id: requireString(json, 'id'),
        type: requireString(json, 'type'),
        displayName: requireString(json, 'displayName'),
        accountNumber: requireString(json, 'accountNumber'),
        accountType: requireString(json, 'accountType'),
        instructions: requireString(json, 'instructions'),
        minimum: json['minimumDeposit'].toString(),
        maximum: json['maximumDeposit'].toString(),
      );

  final String id;
  final String type;
  final String displayName;
  final String accountNumber;
  final String accountType;
  final String instructions;
  final String minimum;
  final String maximum;
}

class FundingMethods {
  const FundingMethods({
    required this.submissionsEnabled,
    required this.methods,
    required this.virtualFunding,
    this.depositBdtPerUsd = '125',
    this.withdrawalBdtPerUsd = '118',
  });

  factory FundingMethods.fromJson(JsonObject json) => FundingMethods(
        submissionsEnabled: json['submissionsEnabled'] == true,
        methods: requireList(json['methods'], FundingMethod.fromJson),
        virtualFunding: json['virtualFunding'] == true,
        depositBdtPerUsd: json['depositBdtPerUsd']?.toString() ?? '125',
        withdrawalBdtPerUsd: json['withdrawalBdtPerUsd']?.toString() ?? '118',
      );

  final bool submissionsEnabled;
  final List<FundingMethod> methods;
  final bool virtualFunding;
  final String depositBdtPerUsd;
  final String withdrawalBdtPerUsd;
}
