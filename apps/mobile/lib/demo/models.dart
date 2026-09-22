import 'dart:convert';

class MarketAsset {
  const MarketAsset({
    required this.id,
    required this.symbol,
    required this.name,
    required this.assetClass,
    required this.price,
    required this.changePercent,
    required this.precision,
    this.quoteAsset = 'USD',
  });

  factory MarketAsset.fromJson(Map<String, dynamic> json) => MarketAsset(
        id: json['id'] as String,
        symbol: json['symbol'] as String,
        name: json['name'] as String,
        assetClass: _displayAssetClass(json['assetClass'] as String),
        price: (json['price'] as num?)?.toDouble() ?? 0,
        changePercent: (json['changePercent'] as num?)?.toDouble() ?? 0,
        precision: (json['precision'] ?? json['pricePrecision']) as int,
        quoteAsset: json['quoteAsset'] as String? ?? 'USD',
      );

  final String id;
  final String symbol;
  final String name;
  final String assetClass;
  final double price;
  final double changePercent;
  final int precision;
  final String quoteAsset;
}

enum TradeSide { buy, sell }

enum ContractDirection { up, down }

enum ContractResult { pending, win, loss, draw }

class DemoPosition {
  const DemoPosition({
    required this.id,
    required this.assetId,
    required this.side,
    required this.stakePaisa,
    required this.quantity,
    required this.entryPrice,
    required this.openedAt,
  });

  final String id;
  final String assetId;
  final TradeSide side;
  final int stakePaisa;
  final double quantity;
  final double entryPrice;
  final DateTime openedAt;
}

class DemoTradeRecord {
  const DemoTradeRecord({
    required this.position,
    required this.exitPrice,
    required this.pnlPaisa,
    required this.closedAt,
  });
  final DemoPosition position;
  final double exitPrice;
  final int pnlPaisa;
  final DateTime closedAt;
}

class TimedContract {
  const TimedContract({
    required this.id,
    required this.assetId,
    required this.direction,
    required this.investmentPaisa,
    required this.entryPrice,
    required this.entryTimestamp,
    required this.expiryTimestamp,
    required this.payoutRate,
    required this.priceSource,
    required this.entrySequence,
    this.expiryPrice,
    this.expirySequence,
    this.settledAt,
    this.result = ContractResult.pending,
  });

  final String id;
  final String assetId;
  final ContractDirection direction;
  final int investmentPaisa;
  final double entryPrice;
  final DateTime entryTimestamp;
  final DateTime expiryTimestamp;
  final double payoutRate;
  final String priceSource;
  final int entrySequence;
  final double? expiryPrice;
  final int? expirySequence;
  final DateTime? settledAt;
  final ContractResult result;

  TimedContract settle(
          double price, int sequence, DateTime time, ContractResult outcome) =>
      TimedContract(
        id: id,
        assetId: assetId,
        direction: direction,
        investmentPaisa: investmentPaisa,
        entryPrice: entryPrice,
        entryTimestamp: entryTimestamp,
        expiryTimestamp: expiryTimestamp,
        payoutRate: payoutRate,
        priceSource: priceSource,
        entrySequence: entrySequence,
        expiryPrice: price,
        expirySequence: sequence,
        settledAt: time,
        result: outcome,
      );
}

class DemoTransaction {
  const DemoTransaction({
    required this.id,
    required this.title,
    required this.amountPaisa,
    required this.createdAt,
  });
  final String id;
  final String title;
  final int amountPaisa;
  final DateTime createdAt;
}

List<MarketAsset> decodeAssets(String source) =>
    (jsonDecode(source) as List<dynamic>)
        .map((item) => MarketAsset.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);

String _displayAssetClass(String value) => switch (value.toUpperCase()) {
      'CRYPTO' => 'Crypto',
      'FOREX' => 'Forex',
      'STOCK' => 'Stocks',
      'INDEX' => 'Indices',
      'COMMODITY' => 'Commodities',
      _ => value,
    };
