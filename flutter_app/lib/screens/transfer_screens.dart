import 'package:flutter/material.dart';
import '../services/api.dart';
import '../widgets.dart';

class TransferListScreen extends StatefulWidget {
  const TransferListScreen({super.key});
  @override
  State<TransferListScreen> createState() => _TransferListScreenState();
}

class _TransferListScreenState extends State<TransferListScreen> {
  int _rev = 0;

  @override
  Widget build(BuildContext context) {
    final myHosp = session.hospitalId;
    return Scaffold(
      floatingActionButton: session.role == 'STAFF'
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('Request stock'),
              onPressed: () async {
                final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const CreateTransferScreen()));
                if (ok == true) setState(() { _rev++; });
              },
            )
          : null,
      body: AsyncBody(
        key: ValueKey(_rev),
        load: () => Api.get('/transfers'),
        builder: (ctx, data, reload) {
          final rows = asList(data);
          if (rows.isEmpty) return emptyList('No transfers yet');
          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 90),
            itemCount: rows.length,
            itemBuilder: (_, i) {
              final t = rows[i];
              final pending = t['status'] == 'PENDING';
              final canSend = pending && (session.role == 'ADMIN' || t['from_hospital_id'] == myHosp);
              final canCancel = pending && (session.role == 'ADMIN' || t['from_hospital_id'] == myHosp || t['to_hospital_id'] == myHosp);
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text('${t['units']} × ${t['blood_group']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      Pill(t['status'] as String),
                    ]),
                    const SizedBox(height: 6),
                    Text('From: ${t['from_hospital']}'),
                    Text('To:   ${t['to_hospital']}'),
                    Text('Requested by ${t['requested_by']} on ${t['created_at']}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    if (canSend || canCancel)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(children: [
                          if (canSend)
                            FilledButton.icon(
                              icon: const Icon(Icons.local_shipping),
                              label: const Text('Dispatch'),
                              onPressed: () async {
                                if (await confirmDialog(ctx, 'Dispatch stock', 'Move ${t['units']} unit(s) of ${t['blood_group']} (earliest expiry first) to ${t['to_hospital']}?')) {
                                  if (!ctx.mounted) return;
                                  await doAction(ctx, () => Api.post('/transfers/${t['transfer_id']}/complete'), ok: 'Transfer completed, both inventories updated');
                                  reload();
                                }
                              },
                            ),
                          const SizedBox(width: 8),
                          if (canCancel)
                            OutlinedButton(
                              onPressed: () async {
                                await doAction(ctx, () => Api.post('/transfers/${t['transfer_id']}/cancel'), ok: 'Transfer cancelled');
                                reload();
                              },
                              child: const Text('Cancel'),
                            ),
                        ]),
                      ),
                  ]),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class CreateTransferScreen extends StatefulWidget {
  const CreateTransferScreen({super.key});
  @override
  State<CreateTransferScreen> createState() => _CreateTransferScreenState();
}

class _CreateTransferScreenState extends State<CreateTransferScreen> {
  final _form = GlobalKey<FormState>();
  int? _from;
  String? _bg;
  final _units = TextEditingController(text: '1');
  bool _busy = false;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() { _busy = true; });
    final ok = await doAction(context, () => Api.post('/transfers', {'from_hospital_id': _from, 'blood_group': _bg, 'units': int.parse(_units.text.trim())}), ok: 'Transfer requested');
    if (!mounted) return;
    setState(() { _busy = false; });
    if (ok) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Request stock transfer')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: Lookups.get(),
        builder: (context, snap) {
          if (!snap.hasData) return snap.hasError ? ErrorView(message: errText(snap.error)) : const Center(child: CircularProgressIndicator());
          final groups = asList(snap.data!['bloodGroups']);
          final hospitals = asList(snap.data!['hospitals']).where((h) => h['hospital_id'] != session.hospitalId).toList();
          return Form(
            key: _form,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              const Text('Ask another hospital to send units to your hospital. They dispatch it; both inventories update together.', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: _from,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Send from'),
                items: [for (final h in hospitals) DropdownMenuItem<int>(value: h['hospital_id'] as int, child: Text('${h['name']} (${h['city']})', overflow: TextOverflow.ellipsis))],
                validator: (v) => v == null ? 'Select a hospital' : null,
                onChanged: (v) => setState(() { _from = v; }),
              ),
              const SizedBox(height: 12),
              BloodGroupField(groups: groups, value: _bg, onChanged: (v) => setState(() { _bg = v; })),
              const SizedBox(height: 12),
              TextFormField(controller: _units, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Units (1-50)'), validator: (v) { final n = int.tryParse(v ?? ''); return (n == null || n < 1 || n > 50) ? 'Enter 1 to 50' : null; }),
              const SizedBox(height: 24),
              SizedBox(height: 48, child: FilledButton(onPressed: _busy ? null : _submit, child: _busy ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Send request'))),
            ]),
          );
        },
      ),
    );
  }
}
