import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class EducationScreen extends StatelessWidget {
  const EducationScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Help & education')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          const Text('How trading works',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          const Text(
              'Trades use a virtual balance. Market prices are references; buying a timed contract does not buy the underlying asset.'),
          const SizedBox(height: 16),
          const ExpansionTile(
            title: Text('How do BUY and SELL work?'),
            children: [
              Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                    'BUY benefits when the reference price rises; SELL benefits when it falls. Profit or loss is proportional to the percentage price move and the amount you stake.'),
              )
            ],
          ),
          const ExpansionTile(
            title: Text('When is a timed trade settled?'),
            children: [
              Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                    'Your stake is locked when the trade opens. At expiry, Zettax uses its recorded price source to calculate the payout and returns any payout to your available balance. If the required price is unavailable, the trade remains pending until it can be settled.'),
              )
            ],
          ),
          const ExpansionTile(
            title: Text('Why can a win return the same amount?'),
            children: [
              Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                    'A very small favorable price move can produce less than \$0.01 of profit. Payouts are rounded to the nearest cent, so the recorded result can be a win while the money returned is unchanged.'),
              )
            ],
          ),
          const ExpansionTile(
            title: Text('Can I withdraw the virtual balance?'),
            children: [
              Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                    'The balance used for trading is virtual. Funding requests and account records are managed separately; virtual trading returns are not a promise of redeemable cash.'),
              )
            ],
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => context.go('/home?tab=2'),
            icon: const Icon(Icons.candlestick_chart),
            label: const Text('Open trading screen'),
          ),
          TextButton(
            onPressed: () => context.push('/risk'),
            child: const Text('Read risk disclosure'),
          ),
        ]),
      );
}

class RiskDisclosureScreen extends StatelessWidget {
  const RiskDisclosureScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Risk disclosure')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          const Text('Understand the risks before trading',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          const ListTile(
            leading: Icon(Icons.trending_down),
            title: Text('You can lose your stake'),
            subtitle: Text(
                'A price move against your direction reduces the payout. The payout cannot fall below zero, but the entire virtual stake can be lost.'),
          ),
          const ListTile(
            leading: Icon(Icons.price_change_outlined),
            title: Text('Displayed prices are estimates'),
            subtitle: Text(
                'Live chart prices can differ from the archived price used at entry and expiry. The running return is an estimate, not a guaranteed payout.'),
          ),
          const ListTile(
            leading: Icon(Icons.schedule_outlined),
            title: Text('Settlement can be delayed'),
            subtitle: Text(
                'If the required expiry observation is unavailable, the trade stays pending. A later price is not substituted.'),
          ),
          const ListTile(
            leading: Icon(Icons.account_balance_wallet_outlined),
            title: Text('Virtual funds'),
            subtitle: Text(
                'The trading balance and returns are virtual. Past performance does not predict future results or create a claim to real funds.'),
          ),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: () => context.push('/education'),
            child: const Text('How timed trades work'),
          ),
        ]),
      );
}
