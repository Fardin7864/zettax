import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum DisplayCurrency { usd, bdt }

final displayCurrencyProvider =
    StateProvider<DisplayCurrency>((ref) => DisplayCurrency.usd);

final usdBdtRateProvider = FutureProvider<double>((ref) async {
  final response = await Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 6),
    receiveTimeout: const Duration(seconds: 6),
  )).get<Map<String, dynamic>>('https://open.er-api.com/v6/latest/USD');
  final rates = response.data?['rates'];
  final rate = rates is Map ? rates['BDT'] : null;
  if (rate is! num || rate <= 0) {
    throw const FormatException('USD/BDT reference rate unavailable');
  }
  return rate.toDouble();
});

class CurrencySelector extends ConsumerWidget {
  const CurrencySelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(displayCurrencyProvider);
    return SegmentedButton<DisplayCurrency>(
      showSelectedIcon: false,
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      segments: const [
        ButtonSegment(value: DisplayCurrency.usd, label: Text('USD')),
        ButtonSegment(value: DisplayCurrency.bdt, label: Text('BDT')),
      ],
      selected: {selected},
      onSelectionChanged: (value) =>
          ref.read(displayCurrencyProvider.notifier).state = value.first,
    );
  }
}

String formatDisplayPrice({
  required double value,
  required int precision,
  required String quoteAsset,
  required DisplayCurrency currency,
  double? usdBdt,
}) {
  if (quoteAsset == 'USD' &&
      currency == DisplayCurrency.bdt &&
      usdBdt != null) {
    return '৳${(value * usdBdt).toStringAsFixed(precision > 2 ? 2 : precision)}';
  }
  final prefix = quoteAsset == 'USD' ? r'$' : '$quoteAsset ';
  return '$prefix${value.toStringAsFixed(precision)}';
}

String formatBdtAmount(
  double bdt,
  DisplayCurrency currency,
  double? usdBdt,
) {
  if (currency == DisplayCurrency.usd && usdBdt != null) {
    return '\$${(bdt / usdBdt).toStringAsFixed(2)}';
  }
  return '৳${bdt.toStringAsFixed(2)}';
}
