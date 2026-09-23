import 'package:flutter_test/flutter_test.dart';
import 'package:primevest_mobile/features/shared/market_widgets.dart';

void main() {
  test('every bundled trade instrument has a real-image source', () {
    const ids = [
      'btc-usd',
      'eth-usd',
      'sol-usd',
      'xrp-usd',
      'ada-usd', 'doge-usd', 'avax-usd', 'dot-usd', 'link-usd',
      'ltc-usd', 'bch-usd', 'trx-usd', 'uni-usd', 'atom-usd',
      'near-usd', 'shib-usd', 'apt-usd', 'sui-usd', 'pepe-usd',
      'eur-usd',
      'gbp-usd',
      'usd-jpy',
      'aud-usd',
      'aapl',
      'msft',
      'nvda',
      'tsla',
      'spx',
      'ndx',
      'dax',
      'xau-usd',
      'xag-usd',
      'oil-usd',
    ];
    for (final id in ids) {
      final urls = AssetIcon.imageUrlsFor(id);
      expect(urls, isNotEmpty, reason: id);
      expect(urls.every((url) => url.startsWith('https://')), isTrue,
          reason: id);
    }
    expect(AssetIcon.imageUrlsFor('unknown'), isEmpty);
  });

  test('forex pairs use both currencies', () {
    for (final id in ['eur-usd', 'gbp-usd', 'usd-jpy', 'aud-usd']) {
      expect(AssetIcon.imageUrlsFor(id), hasLength(2));
    }
  });
}
