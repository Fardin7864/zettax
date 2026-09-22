import 'dart:math' as math;

class ContractEstimate {
  const ContractEstimate({
    required this.returnAmount,
    required this.pnl,
    required this.rawPnl,
  });

  final double returnAmount;
  final double pnl;
  final double rawPnl;
}

// Display-only estimate. The server settles against its archived expiry quote.
ContractEstimate estimateContractReturn({
  required double stake,
  required double entryPrice,
  required double currentPrice,
  required bool up,
  double profitFeeRate = 0,
}) {
  final rawPnl = stake * (currentPrice / entryPrice - 1) * (up ? 1 : -1);
  final grossReturn = math.max(0.0, stake + rawPnl);
  final roundedGross = (grossReturn * 100).round() / 100;
  final grossPnl = roundedGross - stake;
  final fee = (math.max(0.0, grossPnl) * profitFeeRate * 100).round() / 100;
  final returned = roundedGross - fee;
  return ContractEstimate(
      returnAmount: returned, pnl: returned - stake, rawPnl: rawPnl);
}

String contractTimeRemaining(DateTime end, {DateTime? now}) {
  final milliseconds = end.difference(now ?? DateTime.now()).inMilliseconds;
  if (milliseconds <= 0) return 'Awaiting settlement';
  final seconds = (milliseconds / 1000).ceil();
  final days = seconds ~/ 86400;
  final hours = (seconds % 86400) ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final rest = seconds % 60;
  if (days > 0) return '${days}d ${hours}h';
  if (seconds >= 3600) return '${hours}h ${minutes}m';
  return '${minutes.toString().padLeft(2, '0')}:${rest.toString().padLeft(2, '0')}';
}
