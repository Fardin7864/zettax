import 'package:primevest_mobile/core/api/api_contract.dart';

class TradingOrder {
  const TradingOrder({
    required this.id,
    required this.instrumentId,
    required this.side,
    required this.quantity,
    required this.averageFillPrice,
    required this.status,
    required this.positionId,
  });

  factory TradingOrder.fromJson(JsonObject json) => TradingOrder(
        id: requireString(json, 'id'),
        instrumentId: requireString(json, 'instrumentId'),
        side: requireString(json, 'side'),
        quantity: requireString(json, 'quantity'),
        averageFillPrice: json['averageFillPrice'] as String?,
        status: requireString(json, 'status'),
        positionId: json['positionId'] as String?,
      );

  final String id;
  final String instrumentId;
  final String side;
  final String quantity;
  final String? averageFillPrice;
  final String status;
  final String? positionId;
}

class TradingPosition {
  const TradingPosition({
    required this.id,
    required this.instrumentId,
    required this.side,
    required this.quantity,
    required this.averageEntry,
    required this.markPrice,
    required this.realizedPnl,
    required this.unrealizedPnl,
    required this.status,
    required this.openedAt,
  });

  factory TradingPosition.fromJson(JsonObject json) => TradingPosition(
        id: requireString(json, 'id'),
        instrumentId: requireString(json, 'instrumentId'),
        side: requireString(json, 'side'),
        quantity: requireString(json, 'quantity'),
        averageEntry: requireString(json, 'averageEntry'),
        markPrice: requireString(json, 'markPrice'),
        realizedPnl: requireString(json, 'realizedPnl'),
        unrealizedPnl: requireString(json, 'unrealizedPnl'),
        status: requireString(json, 'status'),
        openedAt: requireDateTime(json, 'openedAt'),
      );

  final String id;
  final String instrumentId;
  final String side;
  final String quantity;
  final String averageEntry;
  final String markPrice;
  final String realizedPnl;
  final String unrealizedPnl;
  final String status;
  final DateTime openedAt;
}

class TimedContract {
  const TimedContract({
    required this.id,
    required this.instrumentId,
    required this.direction,
    required this.investmentAmount,
    required this.entryPrice,
    required this.expiryTimestamp,
    required this.result,
    required this.entryTimestamp,
    this.profitFeeRate = '0',
    this.settlementModel = 'FIXED_PAYOUT_V1',
    this.payoutAmount,
    this.feeAmount,
  });

  factory TimedContract.fromJson(JsonObject json) => TimedContract(
        id: requireString(json, 'id'),
        instrumentId: requireString(json, 'instrumentId'),
        direction: requireString(json, 'direction'),
        investmentAmount: requireString(json, 'investmentAmount'),
        entryPrice: requireString(json, 'entryPrice'),
        expiryTimestamp: requireDateTime(json, 'expiryTimestamp'),
        result: requireString(json, 'result'),
        entryTimestamp: requireDateTime(json, 'entryTimestamp'),
        profitFeeRate: json['profitFeeRate'] as String? ?? '0',
        settlementModel:
            json['settlementModel'] as String? ?? 'FIXED_PAYOUT_V1',
        payoutAmount: json['settlement'] is Map
            ? json['settlement']['payoutAmount'] as String?
            : null,
        feeAmount: json['settlement'] is Map
            ? json['settlement']['feeAmount'] as String?
            : null,
      );

  final String id;
  final String instrumentId;
  final String direction;
  final String investmentAmount;
  final String entryPrice;
  final DateTime expiryTimestamp;
  final String result;
  final DateTime entryTimestamp;
  final String profitFeeRate;
  final String settlementModel;
  final String? payoutAmount;
  final String? feeAmount;
}
