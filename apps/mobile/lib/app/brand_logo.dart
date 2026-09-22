import 'package:flutter/material.dart';

abstract final class ZettaxBrandAssets {
  static const mark = 'assets/branding/zettax_mark.png';
  static const wordmark = 'assets/branding/zettax_wordmark.png';
}

class ZettaxMark extends StatelessWidget {
  const ZettaxMark({super.key, this.height = 48});

  final double height;

  @override
  Widget build(BuildContext context) => Image.asset(
        ZettaxBrandAssets.mark,
        height: height,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        semanticLabel: 'Zettax logo',
      );
}

class ZettaxWordmark extends StatelessWidget {
  const ZettaxWordmark({super.key, this.width = 180});

  final double width;

  @override
  Widget build(BuildContext context) => Image.asset(
        ZettaxBrandAssets.wordmark,
        width: width,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        semanticLabel: 'Zettax',
      );
}
