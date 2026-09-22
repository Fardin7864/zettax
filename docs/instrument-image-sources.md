# Instrument images

The mobile app loads images over HTTPS and falls back to the instrument symbol when an image cannot be fetched. Image mapping is keyed by instrument ID in `AssetIcon.imageUrlsFor`.

- BTC, ETH, SOL and XRP: [Spothq cryptocurrency-icons](https://github.com/spothq/cryptocurrency-icons), 128px color PNGs.
- Forex pairs: actual currency flags from [FlagCDN](https://flagcdn.com/), with both sides of the pair displayed.
- AAPL, MSFT, NVDA, TSLA, S&P 500, NASDAQ 100 and DAX: company or index-provider website favicons returned by Google's favicon service. Provider marks identify the source or company; they are not endorsements.
- Gold: [Kjmonkey's gold bullion photo](https://commons.wikimedia.org/wiki/File:Chip_gold_bullion_bar.jpg), CC0.
- Silver: [Kallemax's silver bullion photo](https://commons.wikimedia.org/wiki/File:Johnson_Matthey_500_grammes_silver_bullion.jpg), public domain.
- Oil: [Lexicon's oil barrel image](https://commons.wikimedia.org/wiki/File:Oil_barrel.png), public domain.

The icon imagery is illustrative only and does not affect market prices or settlement.
