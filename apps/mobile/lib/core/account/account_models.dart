import 'package:primevest_mobile/core/api/api_contract.dart';

enum AccountMode {
  demo('DEMO'),
  real('REAL');

  const AccountMode(this.apiValue);
  final String apiValue;
}

class WalletSummary {
  const WalletSummary({
    required this.currency,
    required this.available,
    required this.locked,
    required this.equity,
  });

  factory WalletSummary.fromJson(JsonObject json) => WalletSummary(
        currency: requireString(json, 'currencyCode'),
        available: requireString(json, 'available'),
        locked: requireString(json, 'locked'),
        equity: requireString(json, 'equity'),
      );

  final String currency;
  final String available;
  final String locked;
  final String equity;
}

class AccountSummary {
  const AccountSummary({
    required this.id,
    required this.mode,
    required this.status,
    required this.wallets,
    required this.openPositionCount,
    required this.createdAt,
  });

  factory AccountSummary.fromJson(JsonObject json) => AccountSummary(
        id: requireString(json, 'id'),
        mode: AccountMode.values.firstWhere(
          (mode) => mode.apiValue == requireString(json, 'mode'),
        ),
        status: requireString(json, 'status'),
        wallets: requireList(json['wallets'], WalletSummary.fromJson),
        openPositionCount: json['openPositionCount'] as int,
        createdAt: requireDateTime(json, 'createdAt'),
      );

  final String id;
  final AccountMode mode;
  final String status;
  final List<WalletSummary> wallets;
  final int openPositionCount;
  final DateTime createdAt;
}

class UserProfile {
  const UserProfile({
    required this.fullName,
    required this.dateOfBirth,
    required this.currentAddress,
    required this.district,
    required this.country,
    this.gender,
    this.avatarObjectKey,
  });

  factory UserProfile.fromJson(JsonObject json) => UserProfile(
        fullName: requireString(json, 'fullName'),
        // Birth dates are calendar dates, not instants; never shift time zones.
        dateOfBirth:
            DateTime.parse(requireString(json, 'dateOfBirth').split('T').first),
        gender: json['gender'] as String?,
        avatarObjectKey: json['avatarObjectKey'] as String?,
        currentAddress: json['currentAddress'] as String? ?? '',
        district: json['district'] as String? ?? '',
        country: requireString(json, 'country'),
      );

  final String fullName;
  final DateTime dateOfBirth;
  final String? gender;
  final String? avatarObjectKey;
  final String currentAddress;
  final String district;
  final String country;
}

class CurrentUser {
  const CurrentUser({
    required this.id,
    required this.email,
    this.phone,
    required this.loginEnabled,
    required this.tradingEnabled,
    required this.depositEnabled,
    required this.withdrawalEnabled,
    required this.createdAt,
    this.profile,
  });

  factory CurrentUser.fromJson(JsonObject json) => CurrentUser(
        id: requireString(json, 'id'),
        email: requireString(json, 'email'),
        phone: json['phone'] as String?,
        loginEnabled: json['loginEnabled'] == true,
        tradingEnabled: json['tradingEnabled'] == true,
        depositEnabled: json['depositEnabled'] == true,
        withdrawalEnabled: json['withdrawalEnabled'] == true,
        createdAt: requireDateTime(json, 'createdAt'),
        profile: json['profile'] is Map
            ? UserProfile.fromJson(
                Map<String, dynamic>.from(json['profile'] as Map),
              )
            : null,
      );

  final String id;
  final String email;
  final String? phone;
  final bool loginEnabled;
  final bool tradingEnabled;
  final bool depositEnabled;
  final bool withdrawalEnabled;
  final DateTime createdAt;
  final UserProfile? profile;
}

class PublicSystemConfig {
  const PublicSystemConfig({
    required this.complianceMode,
    required this.demoInitialBalance,
    required this.realTrading,
    required this.realDeposits,
    required this.realWithdrawals,
    required this.realFundsKind,
    required this.serverTime,
  });

  factory PublicSystemConfig.fromJson(JsonObject json) {
    final demo = requireObject(json, 'demo');
    final real = requireObject(json, 'real');
    return PublicSystemConfig(
      complianceMode: requireString(json, 'complianceMode'),
      demoInitialBalance: requireString(demo, 'initialBalanceUsd'),
      realTrading: real['trading'] == true,
      realDeposits: real['deposits'] == true,
      realWithdrawals: real['withdrawals'] == true,
      realFundsKind: real['fundsKind'] == 'VIRTUAL' ? 'VIRTUAL' : 'REAL_MONEY',
      serverTime: requireDateTime(json, 'serverTime'),
    );
  }

  final String complianceMode;
  final String demoInitialBalance;
  final bool realTrading;
  bool tradingAvailableFor(AccountMode mode) =>
      mode == AccountMode.demo || realTrading;
  final bool realDeposits;
  final bool realWithdrawals;
  final String realFundsKind;
  bool get usesVirtualFunds => realFundsKind == 'VIRTUAL';
  final DateTime serverTime;

  static PublicSystemConfig get failClosed => PublicSystemConfig(
        complianceMode: 'DEMO_ONLY',
        demoInitialBalance: '1000.00',
        realTrading: false,
        realDeposits: false,
        realWithdrawals: false,
        realFundsKind: 'REAL_MONEY',
        serverTime: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
}
