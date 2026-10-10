import 'package:flutter/material.dart';
import '../services/api.dart';
import '../widgets.dart';
import 'request_screens.dart';

/// Search usable (non-expired) stock across hospitals. Available to every role.
class InventorySearchScreen extends StatefulWidget {
  const InventorySearchScreen({super.key});
  @override
  State<InventorySearchScreen> createState() => _InventorySearchScreenState();
}

class _InventorySearchScreenState extends State<InventorySearchScreen> {
  String? _bg;
  bool _exact = false;
  final _city = TextEditingController();
  int _rev = 0;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: Lookups.get(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snap.hasError) return ErrorView(message: errText(snap.error), onRetry: () => setState(() {}));
        final groups = asList(snap.data!['bloodGroups']);
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(children: [
              Expanded(child: BloodGroupField(groups: groups, value: _bg, allowAny: true, label: 'Needed blood group', onChanged: (v) => setState(() { _bg = v; _rev++; }))),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _city,
                  decoration: const InputDecoration(labelText: 'City', suffixIcon: Icon(Icons.search)),
                  onSubmitted: (_) => setState(() { _rev++; }),
                ),
              ),
            ]),
          ),
          CheckboxListTile(
            dense: true,
            value: _exact,
            title: const Text('Exact blood group only (hide compatible groups)'),
            onChanged: (v) => setState(() { _exact = v ?? false; _rev++; }),
          ),
          Expanded(
            child: AsyncBody(
              key: ValueKey('$_bg-$_exact-$_rev'),
              load: () => Api.get('/inventory/search', query: {
                if (_bg != null) 'bg': _bg!,
                if (_exact) 'exact': '1',
                if (_city.text.trim().isNotEmpty) 'city': _city.text.trim(),
              }),
              builder: (ctx, data, reload) {
                final rows = asList(data);
                if (rows.isEmpty) return emptyList('No usable stock found for this search');
                return ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(8),
                  itemCount: rows.length,
                  itemBuilder: (_, i) {
                    final r = rows[i];
                    final units = r['units_available'];
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.red.shade50,
                          child: Text('${r['blood_group']}', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red.shade800, fontSize: 13)),
                        ),
                        title: Text('${r['hospital_name']}'),
                        subtitle: Text('${r['city']} • ${r['facility_type'] == 'BLOOD_BANK' ? 'Blood bank' : 'Hospital'} • ☎ ${r['phone']}\nNearest expiry: ${r['nearest_expiry'] ?? '-'}'),
                        isThreeLine: true,
                        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Text('$units', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                          const Text('units', style: TextStyle(fontSize: 11)),
                        ]),
                        onTap: session.role == 'PATIENT'
                            ? () async {
                                final ok = await Navigator.of(ctx).push<bool>(MaterialPageRoute(
                                  builder: (_) => CreateRequestScreen(hospitalId: r['hospital_id'] as int, bg: _bg ?? r['blood_group'] as String),
                                ));
                                if (ok == true) reload();
                              }
                            : null,
                      ),
                    );
                  },
                );
              },
            ),
          ),
          if (session.role == 'PATIENT')
            const Padding(padding: EdgeInsets.all(8), child: Text('Tap a hospital to raise a request there', style: TextStyle(color: Colors.grey, fontSize: 12))),
        ]);
      },
    );
  }
}

/// Staff: batches in own hospital (admin: all) with expiry tracking; record donations.
class BatchesScreen extends StatefulWidget {
  const BatchesScreen({super.key});
  @override
  State<BatchesScreen> createState() => _BatchesScreenState();
}

class _BatchesScreenState extends State<BatchesScreen> {
  int _rev = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Record donation'),
        onPressed: () async {
          final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const RecordDonationScreen()));
          if (ok == true) setState(() { _rev++; });
        },
      ),
      body: AsyncBody(
        key: ValueKey(_rev),
        load: () => Api.get('/inventory/batches'),
        builder: (ctx, data, reload) {
          final rows = asList(data);
          if (rows.isEmpty) return emptyList('No stock batches yet');
          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 90),
            itemCount: rows.length,
            itemBuilder: (_, i) {
              final r = rows[i];
              final days = (r['days_left'] as num).toInt();
              final expired = r['status'] == 'EXPIRED' || days < 0;
              final color = expired ? Colors.red.shade700 : (days <= 5 ? Colors.deepOrange : Colors.green.shade700);
              return Card(
                child: ListTile(
                  leading: CircleAvatar(backgroundColor: color.withAlpha(30), child: Text('${r['blood_group']}', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13))),
                  title: Text('Batch #${r['batch_id']} • ${r['units_available']}/${r['units_total']} units'),
                  subtitle: Text('${r['hospital_name']}\nCollected ${r['collected_on']} • Expires ${r['expiry_date']}'),
                  isThreeLine: true,
                  trailing: Pill(expired ? 'EXPIRED' : (days <= 5 ? '$days d left' : 'OK'), color: color),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class RecordDonationScreen extends StatefulWidget {
  const RecordDonationScreen({super.key, this.donorId});
  final int? donorId;
  @override
  State<RecordDonationScreen> createState() => _RecordDonationScreenState();
}

class _RecordDonationScreenState extends State<RecordDonationScreen> {
  int? _donor;
  int _units = 1;
  bool _busy = false;
  late Future<dynamic> _f;

  @override
  void initState() {
    super.initState();
    _donor = widget.donorId;
    _f = Api.get('/donors', query: {'eligible': '1'});
  }

  Future<void> _save() async {
    if (_donor == null) {
      snack(context, 'Select a donor', error: true);
      return;
    }
    setState(() { _busy = true; });
    final ok = await doAction(context, () => Api.post('/inventory/donations', {'donor_id': _donor, 'units': _units}), ok: 'Donation recorded and stock updated');
    if (!mounted) return;
    setState(() { _busy = false; });
    if (ok) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Record donation')),
      body: FutureBuilder<dynamic>(
        future: _f,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) return ErrorView(message: errText(snap.error));
          final donors = asList(snap.data);
          if (_donor != null && !donors.any((d) => d['donor_id'] == _donor)) _donor = null;
          return ListView(padding: const EdgeInsets.all(16), children: [
            const Text('Only donors who are available and eligible (90+ days since last donation) are listed.', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: _donor,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Donor'),
              items: [for (final d in donors) DropdownMenuItem<int>(value: d['donor_id'] as int, child: Text('${d['full_name']} (${d['blood_group']}, ${d['city']})'))],
              onChanged: (v) => setState(() { _donor = v; }),
            ),
            const SizedBox(height: 16),
            SegmentedButton<int>(
              segments: const [ButtonSegment(value: 1, label: Text('1 unit')), ButtonSegment(value: 2, label: Text('2 units'))],
              selected: {_units},
              onSelectionChanged: (s) => setState(() { _units = s.first; }),
            ),
            const SizedBox(height: 8),
            const Text('Blood units get a 35-day expiry automatically.', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 24),
            SizedBox(height: 48, child: FilledButton(onPressed: _busy ? null : _save, child: _busy ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save donation'))),
          ]);
        },
      ),
    );
  }
}

/// Staff/admin: search donors by blood group / city
class DonorsScreen extends StatefulWidget {
  const DonorsScreen({super.key});
  @override
  State<DonorsScreen> createState() => _DonorsScreenState();
}

class _DonorsScreenState extends State<DonorsScreen> {
  String? _bg;
  int _rev = 0;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: Lookups.get(),
      builder: (context, snap) {
        if (!snap.hasData) return snap.hasError ? ErrorView(message: errText(snap.error)) : const Center(child: CircularProgressIndicator());
        final groups = asList(snap.data!['bloodGroups']);
        return Column(children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: BloodGroupField(groups: groups, value: _bg, allowAny: true, label: 'Filter by blood group', onChanged: (v) => setState(() { _bg = v; _rev++; })),
          ),
          Expanded(
            child: AsyncBody(
              key: ValueKey('$_bg-$_rev'),
              load: () => Api.get('/donors', query: {if (_bg != null) 'bg': _bg!}),
              builder: (ctx, data, reload) {
                final rows = asList(data);
                if (rows.isEmpty) return emptyList('No donors found');
                return ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: rows.length,
                  itemBuilder: (_, i) {
                    final d = rows[i];
                    final ok = truthy(d['eligible']);
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(backgroundColor: Colors.red.shade50, child: Text('${d['blood_group']}', style: TextStyle(color: Colors.red.shade800, fontWeight: FontWeight.bold, fontSize: 13))),
                        title: Text('${d['full_name']}'),
                        subtitle: Text('${d['city']} • ☎ ${d['phone']}\nLast donation: ${d['last_donation_date'] ?? 'never'} • ${d['total_donations']} total'),
                        isThreeLine: true,
                        trailing: Pill(ok ? 'ELIGIBLE' : 'WAIT', color: ok ? Colors.green.shade700 : Colors.orange.shade800),
                        onTap: ok
                            ? () async {
                                final saved = await Navigator.of(ctx).push<bool>(MaterialPageRoute(builder: (_) => RecordDonationScreen(donorId: d['donor_id'] as int)));
                                if (saved == true) reload();
                              }
                            : null,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ]);
      },
    );
  }
}
