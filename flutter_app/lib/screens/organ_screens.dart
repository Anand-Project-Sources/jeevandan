import 'package:flutter/material.dart';
import '../services/api.dart';
import '../widgets.dart';

const _disclaimer =
    'This app records pledges and supports eligibility verification only. It never allocates organs automatically. '
    'Allocation and any donor/family contact must follow the Transplantation of Human Organs Act and the authorised '
    'transplant committee / NOTTO-SOTTO protocol.';

// ---------------- Donor: organ pledge (consent) ----------------
class OrganConsentScreen extends StatelessWidget {
  const OrganConsentScreen({super.key});

  Future<List<dynamic>> _load() => Future.wait([Lookups.get(), Api.get('/organ/consents')]);

  @override
  Widget build(BuildContext context) {
    return AsyncBody(
      load: _load,
      builder: (ctx, data, reload) {
        final parts = data as List<dynamic>;
        final organs = asList(asMap(parts[0])['organs']);
        final consents = {for (final c in asList(parts[1])) c['organ_id']: c};
        return ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(12), children: [
          Card(color: Colors.blue.shade50, child: const Padding(padding: EdgeInsets.all(12), child: Text(_disclaimer, style: TextStyle(fontSize: 12)))),
          for (final o in organs)
            Builder(builder: (_) {
              final c = consents[o['organ_id']];
              final given = c != null && c['status'] == 'GIVEN';
              return Card(
                child: SwitchListTile(
                  title: Text('${o['organ_name']}'),
                  subtitle: Text(c == null ? 'Not pledged' : (given ? 'Pledged on ${c['consent_date']}${c['witness_name'] != null ? ' • witness ${c['witness_name']}' : ''}' : 'Withdrawn on ${c['consent_date']}')),
                  value: given,
                  onChanged: (v) async {
                    Map<String, dynamic> body;
                    if (v) {
                      final r = await showDialog<Map<String, dynamic>>(context: ctx, builder: (_) => const _ConsentDialog());
                      if (r == null) return;
                      body = {'organ_id': o['organ_id'], 'status': 'GIVEN', ...r};
                    } else {
                      if (!await confirmDialog(ctx, 'Withdraw pledge', 'Withdraw your pledge for ${o['organ_name']}?')) return;
                      body = {'organ_id': o['organ_id'], 'status': 'WITHDRAWN'};
                    }
                    if (!ctx.mounted) return;
                    await doAction(ctx, () => Api.put('/organ/consents', body), ok: 'Consent updated');
                    reload();
                  },
                ),
              );
            }),
        ]);
      },
    );
  }
}

class _ConsentDialog extends StatefulWidget {
  const _ConsentDialog();
  @override
  State<_ConsentDialog> createState() => _ConsentDialogState();
}

class _ConsentDialogState extends State<_ConsentDialog> {
  final _witness = TextEditingController();
  bool _family = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Organ donation pledge'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Your family should know your wishes. You can withdraw this pledge any time.', style: TextStyle(fontSize: 13)),
        const SizedBox(height: 12),
        TextField(controller: _witness, decoration: const InputDecoration(labelText: 'Witness name (optional)')),
        CheckboxListTile(contentPadding: EdgeInsets.zero, value: _family, onChanged: (v) => setState(() { _family = v ?? false; }), title: const Text('I have informed my family', style: TextStyle(fontSize: 14))),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _family ? () => Navigator.pop(context, {'family_informed': true, if (_witness.text.trim().isNotEmpty) 'witness_name': _witness.text.trim()}) : null,
          child: const Text('Pledge'),
        ),
      ],
    );
  }
}

// ---------------- Staff / Admin: organ requests ----------------
class OrganRequestListScreen extends StatefulWidget {
  const OrganRequestListScreen({super.key});
  @override
  State<OrganRequestListScreen> createState() => _OrganRequestListScreenState();
}

class _OrganRequestListScreenState extends State<OrganRequestListScreen> {
  int _rev = 0;
  bool get _canCreate => session.role == 'STAFF' && truthy(session.user?['is_transplant_center']);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: _canCreate
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('Organ request'),
              onPressed: () async {
                final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const CreateOrganRequestScreen()));
                if (ok == true) setState(() { _rev++; });
              },
            )
          : null,
      body: AsyncBody(
        key: ValueKey(_rev),
        load: () => Api.get('/organ/requests'),
        builder: (ctx, data, reload) {
          final rows = asList(data);
          return ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.fromLTRB(8, 8, 8, 90), children: [
            Card(color: Colors.blue.shade50, child: const Padding(padding: EdgeInsets.all(12), child: Text(_disclaimer, style: TextStyle(fontSize: 12)))),
            if (rows.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No organ requests', style: TextStyle(color: Colors.grey)))),
            for (final r in rows)
              Card(
                child: ListTile(
                  leading: CircleAvatar(backgroundColor: Colors.red.shade50, child: Text('${r['blood_group']}', style: TextStyle(color: Colors.red.shade800, fontWeight: FontWeight.bold, fontSize: 13))),
                  title: Text('${r['organ_name']} • ${r['patient_name']} (${r['patient_age']})'),
                  subtitle: Text('${r['hospital_name']}\n${r['created_at']}'),
                  isThreeLine: true,
                  trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [Pill(r['status'] as String), const SizedBox(height: 4), Pill(r['urgency'] as String)]),
                  onTap: () async {
                    await Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => OrganRequestDetailScreen(id: r['organ_request_id'] as int)));
                    reload();
                  },
                ),
              ),
          ]);
        },
      ),
    );
  }
}

class CreateOrganRequestScreen extends StatefulWidget {
  const CreateOrganRequestScreen({super.key});
  @override
  State<CreateOrganRequestScreen> createState() => _CreateOrganRequestScreenState();
}

class _CreateOrganRequestScreenState extends State<CreateOrganRequestScreen> {
  final _form = GlobalKey<FormState>();
  int? _organ;
  String? _bg;
  String _urgency = 'NORMAL';
  final _name = TextEditingController();
  final _age = TextEditingController();
  bool _busy = false;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() { _busy = true; });
    final ok = await doAction(context, () => Api.post('/organ/requests', {
          'organ_id': _organ, 'blood_group': _bg, 'patient_name': _name.text.trim(),
          'patient_age': int.parse(_age.text.trim()), 'urgency': _urgency,
        }), ok: 'Organ request submitted for verification');
    if (!mounted) return;
    setState(() { _busy = false; });
    if (ok) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New organ request')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: Lookups.get(),
        builder: (context, snap) {
          if (!snap.hasData) return snap.hasError ? ErrorView(message: errText(snap.error)) : const Center(child: CircularProgressIndicator());
          final organs = asList(snap.data!['organs']);
          final groups = asList(snap.data!['bloodGroups']);
          return Form(
            key: _form,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              DropdownButtonFormField<int>(
                value: _organ,
                decoration: const InputDecoration(labelText: 'Organ needed'),
                items: [for (final o in organs) DropdownMenuItem<int>(value: o['organ_id'] as int, child: Text('${o['organ_name']}'))],
                validator: (v) => v == null ? 'Select an organ' : null,
                onChanged: (v) => setState(() { _organ = v; }),
              ),
              const SizedBox(height: 12),
              BloodGroupField(groups: groups, value: _bg, label: 'Patient blood group', onChanged: (v) => setState(() { _bg = v; })),
              const SizedBox(height: 12),
              TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Patient name'), validator: (v) => (v == null || v.trim().length < 2) ? 'Enter patient name' : null),
              const SizedBox(height: 12),
              TextFormField(controller: _age, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Patient age'), validator: (v) { final n = int.tryParse(v ?? ''); return (n == null || n < 0 || n > 120) ? 'Enter a valid age' : null; }),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _urgency,
                decoration: const InputDecoration(labelText: 'Urgency'),
                items: const [DropdownMenuItem(value: 'NORMAL', child: Text('Normal')), DropdownMenuItem(value: 'URGENT', child: Text('Urgent')), DropdownMenuItem(value: 'CRITICAL', child: Text('Critical'))],
                onChanged: (v) => setState(() { _urgency = v ?? 'NORMAL'; }),
              ),
              const SizedBox(height: 12),
              const Text('The request is reviewed by the authorised verifier before any donor information is shown.', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 20),
              SizedBox(height: 48, child: FilledButton(onPressed: _busy ? null : _submit, child: _busy ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Submit'))),
            ]),
          );
        },
      ),
    );
  }
}

class OrganRequestDetailScreen extends StatelessWidget {
  const OrganRequestDetailScreen({super.key, required this.id});
  final int id;

  Future<void> _decide(BuildContext ctx, VoidCallback reload, String decision, String title) async {
    final notes = await textPrompt(ctx, title, hint: 'Verification notes (min 5 characters)', minLen: 5);
    if (notes == null || !ctx.mounted) return;
    await doAction(ctx, () => Api.post('/organ/requests/$id/verify', {'decision': decision, 'notes': notes}), ok: 'Status updated');
    reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Organ request #$id')),
      body: AsyncBody(
        load: () => Api.get('/organ/requests/$id'),
        builder: (ctx, data, reload) {
          final r = asMap(data);
          final status = r['status'] as String;
          final isAdmin = session.role == 'ADMIN';
          return ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(12), children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text('${r['organ_name']} • ${r['blood_group']}', style: Theme.of(ctx).textTheme.titleLarge)),
                    Pill(status),
                    const SizedBox(width: 6),
                    Pill(r['urgency'] as String),
                  ]),
                  const Divider(),
                  InfoRow('Patient', '${r['patient_name']} (${r['patient_age']} yrs)'),
                  InfoRow('Hospital', '${r['hospital_name']}'),
                  InfoRow('Requested by', '${r['requested_by']}'),
                  InfoRow('Created', '${r['created_at']}'),
                  if (r['verified_by'] != null) InfoRow('Verified by', '${r['verified_by']}'),
                  if (r['verification_notes'] != null) InfoRow('Notes', '${r['verification_notes']}'),
                ]),
              ),
            ),
            if (isAdmin && status == 'PENDING')
              Row(children: [
                Expanded(child: FilledButton(onPressed: () => _decide(ctx, reload, 'UNDER_REVIEW', 'Start eligibility review'), child: const Text('Start review'))),
                const SizedBox(width: 8),
                Expanded(child: OutlinedButton(onPressed: () => _decide(ctx, reload, 'REJECTED', 'Reject request'), child: const Text('Reject'))),
              ]),
            if (isAdmin && status == 'UNDER_REVIEW')
              Row(children: [
                Expanded(child: FilledButton(onPressed: () => _decide(ctx, reload, 'VERIFIED', 'Mark eligibility verified'), child: const Text('Verify eligibility'))),
                const SizedBox(width: 8),
                Expanded(child: OutlinedButton(onPressed: () => _decide(ctx, reload, 'REJECTED', 'Reject request'), child: const Text('Reject'))),
              ]),
            if (isAdmin && status == 'VERIFIED')
              OutlinedButton(onPressed: () => _decide(ctx, reload, 'CLOSED', 'Close request'), child: const Text('Close request')),
            if (status == 'UNDER_REVIEW' || status == 'VERIFIED') ...[
              const SectionTitle('Compatible pledged donors (clinical review only)'),
              _Candidates(id: id),
            ],
          ]);
        },
      ),
    );
  }
}

class _Candidates extends StatelessWidget {
  const _Candidates({required this.id});
  final int id;
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<dynamic>(
      future: Api.get('/organ/requests/$id/candidates'),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
        if (snap.hasError) return Padding(padding: const EdgeInsets.all(8), child: Text(errText(snap.error)));
        final d = asMap(snap.data);
        final cands = asList(d['candidates']);
        return Column(children: [
          Card(color: Colors.amber.shade50, child: Padding(padding: const EdgeInsets.all(10), child: Text('${d['notice']}', style: const TextStyle(fontSize: 12)))),
          if (cands.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('No consenting compatible donors on record.')),
          for (final c in cands)
            Card(child: ListTile(dense: true, leading: CircleAvatar(child: Text('${c['blood_group']}', style: const TextStyle(fontSize: 12))), title: Text('Donor #${c['donor_id']} • age ${c['age']} • ${c['city']}'), subtitle: Text('Pledged ${c['consent_date']} • family informed: ${truthy(c['family_informed']) ? 'yes' : 'no'}'))),
        ]);
      },
    );
  }
}
