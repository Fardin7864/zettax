import 'package:flutter/material.dart';

class CurrencySelector extends StatelessWidget {
  const CurrencySelector({super.key});

  @override
  Widget build(BuildContext context) => const Text('USD');
}

String formatDisplayPrice({
  required double value,
  required int precision,
  required String quoteAsset,
}) {
  final prefix = quoteAsset == 'USD' ? r'$' : '$quoteAsset ';
  return '$prefix${value.toStringAsFixed(precision)}';
}

String formatUsdAmount(double usd) => '\$${usd.toStringAsFixed(2)}';
