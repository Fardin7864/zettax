import 'package:flutter/material.dart';

class FundingBrand {
  const FundingBrand(this.name, this.color, this.imageUrl);

  final String name;
  final Color color;
  final String imageUrl;

  static FundingBrand? forType(String? type) => switch (type?.toUpperCase()) {
        'BKASH' => const FundingBrand('bKash', Color(0xFFE2136E),
            'https://commons.wikimedia.org/wiki/Special:FilePath/Bkash.webp?width=128'),
        'NAGAD' => const FundingBrand('Nagad', Color(0xFFF7941D),
            'https://www.nagad.com.bd/_nuxt/img/new-logo.14fe8a5.png'),
        'ROCKET' => const FundingBrand('Rocket', Color(0xFF6A2C91),
            'https://commons.wikimedia.org/wiki/Special:FilePath/Rocket_ddbl.png?width=128'),
        _ => null,
      };
}

class FundingBrandLogo extends StatelessWidget {
  const FundingBrandLogo(
      {super.key, required this.type, this.width = 54, this.height = 36});

  final String? type;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final brand = FundingBrand.forType(type);
    if (brand == null) {
      return SizedBox(
          width: width,
          height: height,
          child: const Icon(Icons.account_balance_wallet_outlined));
    }
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Image.network(
        brand.imageUrl,
        fit: BoxFit.contain,
        cacheWidth: 160,
        errorBuilder: (_, __, ___) => Center(
          child: Text(brand.name,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: brand.color,
                  fontWeight: FontWeight.w900,
                  fontSize: width < 48 ? 8 : 10)),
        ),
      ),
    );
  }
}
