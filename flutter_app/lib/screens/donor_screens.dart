import 'package:flutter/material.dart';
import '../services/api.dart';
import '../widgets.dart';

class DonorHome extends StatelessWidget {
  const DonorHome({super.key});

  Future<List<dynamic>> _load() => Future.wait([
        Api.get('/me'),
        Api.get('/donors/me/history'),
        Api.get('/requests/matches/mine'),
      ]);

  @override
  Widget build(BuildContext context) {
    return AsyncBody(
      load: _load,
      builder: (ctx, data, reload) {
        final parts = data as List<dynamic>;
        final me = asMap(parts[0]);
        final donor = asMap(me['donor']);
        final history = asList(parts[1]);
        final matches = asList(parts[2]);
        final eligible = truthy(donor['eligible']);
        return ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(12), children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  CircleAvatar(radius: 28, backgroundColor: Colors.red.shade50, child: Text('${donor['blood_group']}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.red.shade800))),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${me['full_name']}', style: Theme.of(ctx).textTheme.titleLarge),
                    Text('${donor['city']} • ${history.length} donation(s)'),
                  ])),
                  Pill(eligible ? 'ELIGIBLE' : 'WAIT', color: eligible ? Colors.green.shade700 : Colors.orange.shade800),
                ]),
                if (!eligible) Padding(padding: const EdgeInsets.only(top: 8), child: Text('You can donate again on ${donor['next_eligible_date']}')),
                const Divider(),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Available to donate'),
                  subtitle: const Text('Hospitals can invite you for matching requests'),
                  value: truthy(donor['is_available']),
                  onChanged: (v) async {
                    await doAction(ctx, () => Api.put('/me', {'donor': {'is_available': v}}));
                    reload();
                  },
                ),
              ]),
            ),
          ),
          const SectionTitle('Invitations from hospitals'),
          if (matches.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('No invitations yet.', style: TextStyle(color: Colors.grey))),
          for (final m in matches)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text('${m['units_needed']} unit(s) of ${m['blood_group']} needed', style: const TextStyle(fontWeight: FontWeight.bold))),
                    Pill(m['priority'] as String),
                  ]),
                  Text('${m['hospital_name']}, ${m['city']} • ☎ ${m['hospital_phone']}'),
                  const SizedBox(height: 8),
                  if (m['status'] == 'NOTIFIED')
                    Row(children: [
                      FilledButton(onPressed: () async { await doAction(ctx, () => Api.post('/requests/matches/${m['match_id']}/respond', {'accept': true}), ok: 'Thank you! The hospital has been told.'); reload(); }, child: const Text('I can donate')),
                      const SizedBox(width: 8),
                      OutlinedButton(onPressed: () async { await doAction(ctx, () => Api.post('/requests/matches/${m['match_id']}/respond', {'accept': false})); reload(); }, child: const Text('Not now')),
                    ])
                  else
                    Pill(m['status'] as String),
                ]),
              ),
            ),
          const SectionTitle('Donation history'),
          if (history.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('No donations recorded yet.', style: TextStyle(color: Colors.grey))),
          for (final h in history)
            Card(child: ListTile(leading: const Icon(Icons.bloodtype, color: Colors.red), title: Text('${h['units']} unit(s) on ${h['donated_on']}'), subtitle: Text('${h['hospital_name']}, ${h['city']}'))),
          const SizedBox(height: 30),
        ]);
      },
    );
  }
}
