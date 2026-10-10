import 'package:flutter/material.dart';
import '../services/api.dart';
import '../widgets.dart';

class RequestListScreen extends StatefulWidget {
  const RequestListScreen({super.key});
  @override
  State<RequestListScreen> createState() => _RequestListScreenState();
}

class _RequestListScreenState extends State<RequestListScreen> {
  String _status = 'ALL';
  int _rev = 0;

  bool get _canCreate => session.role == 'PATIENT' || session.role == 'STAFF';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: _canCreate
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('New request'),
              onPressed: () async {
                final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const CreateRequestScreen()));
                if (ok == true) setState(() { _rev++; });
              },
            )
          : null,
      body: Column(children: [
        SizedBox(
          height: 54,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            children: [
              for (final s in ['ALL', 'PENDING', 'APPROVED', 'FULFILLED', 'REJECTED'])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(label: Text(s), selected: _status == s, onSelected: (_) => setState(() { _status = s; })),
                ),
            ],
          ),
        ),
        Expanded(
          child: AsyncBody(
            key: ValueKey('$_status-$_rev'),
            load: () => Api.get('/requests', query: _status == 'ALL' ? null : {'status': _status}),
            builder: (ctx, data, reload) {
              final items = asList(data);
              if (items.isEmpty) return emptyList('No requests found');
              return ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 90),
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final r = items[i];
                  final pc = statusColor(r['priority'] as String);
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(backgroundColor: pc.withAlpha(40), child: Text('${r['blood_group']}', style: TextStyle(fontWeight: FontWeight.bold, color: pc, fontSize: 13))),
                      title: Text('${r['units_needed']} unit(s) • ${r['patient_name']}'),
                      subtitle: Text('${r['hospital_name']}\n${r['created_at']}'),
                      isThreeLine: true,
                      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Pill(r['status'] as String),
                        const SizedBox(height: 4),
                        Pill(r['priority'] as String),
                      ]),
                      onTap: () async {
                        await Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => RequestDetailScreen(id: r['request_id'] as int)));
                        reload();
                      },
                    ),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}

class CreateRequestScreen extends StatefulWidget {
  const CreateRequestScreen({super.key, this.hospitalId, this.bg});
  final int? hospitalId;
  final String? bg;
  @override
  State<CreateRequestScreen> createState() => _CreateRequestScreenState();
}

class _CreateRequestScreenState extends State<CreateRequestScreen> {
  final _form = GlobalKey<FormState>();
  late Future<Map<String, dynamic>> _look;
  int? _hospital;
  String? _bg;
  String _priority = 'NORMAL';
  bool _busy = false;
  final _units = TextEditingController(text: '1');
  final _patient = TextEditingController();
  final _reason = TextEditingController();

  @override
  void initState() {
    super.initState();
    _look = Lookups.get();
    _hospital = widget.hospitalId ?? (session.role == 'STAFF' ? session.hospitalId : null);
    _bg = widget.bg;
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() { _busy = true; });
    final ok = await doAction(
      context,
      () => Api.post('/requests', {
        'hospital_id': _hospital,
        'blood_group': _bg,
        'units_needed': int.parse(_units.text.trim()),
        'priority': _priority,
        'patient_name': _patient.text.trim(),
        'reason': _reason.text.trim(),
      }),
      ok: 'Request submitted',
    );
    if (!mounted) return;
    setState(() { _busy = false; });
    if (ok) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New blood request')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _look,
        builder: (context, snap) {
          if (!snap.hasData) return snap.hasError ? ErrorView(message: errText(snap.error)) : const Center(child: CircularProgressIndicator());
          final groups = asList(snap.data!['bloodGroups']);
          final hospitals = asList(snap.data!['hospitals']);
          return Form(
            key: _form,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'NORMAL', label: Text('Normal')),
                  ButtonSegment(value: 'URGENT', label: Text('Urgent')),
                  ButtonSegment(value: 'EMERGENCY', label: Text('Emergency')),
                ],
                selected: {_priority},
                onSelectionChanged: (s) => setState(() { _priority = s.first; }),
              ),
              if (_priority == 'EMERGENCY')
                Container(
                  margin: const EdgeInsets.only(top: 10),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
                  child: const Text('Emergency requests jump to the top of the hospital queue and alert staff immediately. Use only for life-threatening need.', style: TextStyle(fontSize: 12)),
                ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                value: _hospital,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Hospital / blood bank'),
                items: [for (final h in hospitals) DropdownMenuItem<int>(value: h['hospital_id'] as int, child: Text('${h['name']} (${h['city']})', overflow: TextOverflow.ellipsis))],
                validator: (v) => v == null ? 'Select a hospital' : null,
                onChanged: (v) => setState(() { _hospital = v; }),
              ),
              const SizedBox(height: 12),
              BloodGroupField(groups: groups, value: _bg, onChanged: (v) => setState(() { _bg = v; })),
              const SizedBox(height: 12),
              TextFormField(
                controller: _units,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Units needed (1-20)'),
                validator: (v) { final n = int.tryParse(v ?? ''); return (n == null || n < 1 || n > 20) ? 'Enter 1 to 20' : null; },
              ),
              const SizedBox(height: 12),
              TextFormField(controller: _patient, decoration: const InputDecoration(labelText: 'Patient name'), validator: (v) => (v == null || v.trim().length < 2) ? 'Enter patient name' : null),
              const SizedBox(height: 12),
              TextFormField(controller: _reason, maxLines: 2, decoration: const InputDecoration(labelText: 'Reason / diagnosis (optional)')),
              const SizedBox(height: 24),
              SizedBox(height: 48, child: FilledButton(onPressed: _busy ? null : _submit, child: _busy ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Submit request'))),
            ]),
          );
        },
      ),
    );
  }
}

class RequestDetailScreen extends StatefulWidget {
  const RequestDetailScreen({super.key, required this.id});
  final int id;
  @override
  State<RequestDetailScreen> createState() => _RequestDetailScreenState();
}

class _RequestDetailScreenState extends State<RequestDetailScreen> {
  final Set<int> _selected = {};

  Future<Map<String, dynamic>> _load() async {
    final d = asMap(await Api.get('/requests/${widget.id}'));
    final status = d['request']['status'];
    if (d['can_manage'] == true && (status == 'PENDING' || status == 'APPROVED')) {
      d['matches'] = asMap(await Api.get('/requests/${widget.id}/matches'));
    }
    return d;
  }

  Future<void> _act(VoidCallback reload, Future<dynamic> Function() fn, String ok) async {
    await doAction(context, fn, ok: ok);
    reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Request #${widget.id}')),
      body: AsyncBody(
        load: _load,
        builder: (ctx, data, reload) {
          final d = asMap(data);
          final r = asMap(d['request']);
          final manage = d['can_manage'] == true;
          final status = r['status'] as String;
          final allocations = asList(d['allocations']);
          final matches = d['matches'] == null ? null : asMap(d['matches']);
          return ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(12), children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text('${r['blood_group']}', style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
                    const SizedBox(width: 12),
                    Text('${r['units_needed']} unit(s)', style: Theme.of(context).textTheme.titleLarge),
                    const Spacer(),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Pill(status), const SizedBox(height: 4), Pill(r['priority'] as String)]),
                  ]),
                  const Divider(),
                  InfoRow('Patient', '${r['patient_name']}'),
                  InfoRow('Hospital', '${r['hospital_name']}, ${r['city']}'),
                  InfoRow('Reason', '${r['reason'] ?? '-'}'),
                  InfoRow('Requested by', '${r['requester_name']}'),
                  InfoRow('Created', '${r['created_at']}'),
                  if (r['remarks'] != null) InfoRow('Remarks', '${r['remarks']}'),
                  if (r['fulfilled_at'] != null) InfoRow('Fulfilled', '${r['fulfilled_at']}'),
                  if (manage) InfoRow('Donors', '${d['donors_invited']} invited, ${d['donors_accepted']} accepted'),
                ]),
              ),
            ),
            if (allocations.isNotEmpty) ...[
              const SectionTitle('Units supplied'),
              for (final a in allocations)
                Card(child: ListTile(leading: const Icon(Icons.check_circle, color: Colors.green), title: Text('${a['units_allocated']} unit(s) of ${a['blood_group']}'), subtitle: Text('Batch #${a['batch_id']} • expiry ${a['expiry_date']}'))),
            ],
            if (manage && status == 'PENDING')
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(children: [
                  Expanded(child: FilledButton.icon(icon: const Icon(Icons.verified), label: const Text('Verify & approve'), onPressed: () => _act(reload, () => Api.post('/requests/${widget.id}/approve'), 'Request approved'))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.close),
                      label: const Text('Reject'),
                      onPressed: () async {
                        final why = await textPrompt(ctx, 'Reason for rejection');
                        if (why != null) await _act(reload, () => Api.post('/requests/${widget.id}/reject', {'remarks': why}), 'Request rejected');
                      },
                    ),
                  ),
                ]),
              ),
            if (manage && status == 'APPROVED')
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.bloodtype),
                      label: const Text('Fulfil from stock'),
                      onPressed: () async {
                        if (await confirmDialog(ctx, 'Fulfil request', 'Deduct ${r['units_needed']} unit(s) from unexpired stock (earliest expiry first)?')) {
                          await _act(reload, () => Api.post('/requests/${widget.id}/fulfil'), 'Request fulfilled, inventory updated');
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () async {
                      final why = await textPrompt(ctx, 'Reason for rejection');
                      if (why != null) await _act(reload, () => Api.post('/requests/${widget.id}/reject', {'remarks': why}), 'Request rejected');
                    },
                    child: const Text('Reject'),
                  ),
                ]),
              ),
            if (matches != null) ...[
              const SectionTitle('Matching stock (compatible, unexpired)'),
              if (asList(matches['stock']).isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('No compatible stock anywhere. Invite donors below.')),
              for (final s in asList(matches['stock']))
                Card(
                  child: ListTile(
                    dense: true,
                    leading: Icon(s['hospital_id'] == r['hospital_id'] ? Icons.home_work : Icons.local_hospital, color: s['hospital_id'] == r['hospital_id'] ? Colors.green : Colors.blueGrey),
                    title: Text('${s['hospital_name']} • ${s['blood_group']}'),
                    subtitle: Text('${s['city']} • nearest expiry ${s['nearest_expiry']}${s['hospital_id'] == r['hospital_id'] ? ' • THIS HOSPITAL' : ''}'),
                    trailing: Text('${s['units_available']} u', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              SectionTitle('Eligible donors', trailing: FilledButton.tonal(
                onPressed: _selected.isEmpty
                    ? null
                    : () async {
                        final ok = await doAction(ctx, () => Api.post('/requests/${widget.id}/notify-donors', {'donor_ids': _selected.toList()}), ok: 'Donors notified');
                        if (ok) _selected.clear();
                        reload();
                      },
                child: Text('Notify (${_selected.length})'),
              )),
              if (asList(matches['donors']).isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('No eligible donors found.')),
              for (final dn in asList(matches['donors']))
                Card(
                  child: CheckboxListTile(
                    dense: true,
                    value: _selected.contains(dn['donor_id']) || truthy(dn['already_notified']),
                    onChanged: truthy(dn['already_notified'])
                        ? null
                        : (v) => setState(() {
                              if (v == true) {
                                _selected.add(dn['donor_id'] as int);
                              } else {
                                _selected.remove(dn['donor_id']);
                              }
                            }),
                    title: Text('${dn['full_name']} • ${dn['blood_group']}'),
                    subtitle: Text('${dn['city']}${truthy(dn['same_city']) ? ' (same city)' : ''} • ☎ ${dn['phone']}${truthy(dn['already_notified']) ? ' • already invited' : ''}'),
                  ),
                ),
            ],
            const SizedBox(height: 40),
          ]);
        },
      ),
    );
  }
}
