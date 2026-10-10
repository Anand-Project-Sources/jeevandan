import 'package:flutter/material.dart';
import '../services/api.dart';
import '../widgets.dart';
import 'request_screens.dart';

Widget _stat(BuildContext c, String label, Object value, IconData icon, {Color? color}) {
  final col = color ?? Theme.of(c).colorScheme.primary;
  return SizedBox(
    width: 160,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: col),
          const SizedBox(height: 6),
          Text('$value', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: col)),
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ]),
      ),
    ),
  );
}

// ---------------- Admin dashboard ----------------
class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return AsyncBody(
      load: () => Future.wait([Api.get('/admin/stats'), Api.get('/requests/emergency')]),
      builder: (ctx, data, reload) {
        final parts = data as List<dynamic>;
        final s = asMap(parts[0]);
        final emergencies = asList(parts[1]);
        final counts = asMap(s['counts']);
        final stock = asList(s['stock']);
        final maxUnits = stock.fold<num>(1, (m, e) => (e['units'] as num) > m ? e['units'] as num : m);
        return ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(8), children: [
          Wrap(children: [
            _stat(ctx, 'Donors', counts['donors'], Icons.volunteer_activism),
            _stat(ctx, 'Hospitals / banks', counts['hospitals'], Icons.local_hospital),
            _stat(ctx, 'Patients', counts['patients'], Icons.personal_injury),
            _stat(ctx, 'Staff accounts', counts['staff'], Icons.badge),
            _stat(ctx, 'Units in stock', s['total_units'], Icons.bloodtype, color: Colors.green.shade700),
            _stat(ctx, 'Open emergencies', s['emergencies_open'], Icons.emergency, color: Colors.red.shade700),
            _stat(ctx, 'Units expiring ≤7d', s['expiring_units'], Icons.timer, color: Colors.deepOrange),
            _stat(ctx, 'Pending transfers', s['pending_transfers'], Icons.swap_horiz, color: Colors.blue.shade700),
            _stat(ctx, 'Organ reviews pending', s['pending_organ_requests'], Icons.favorite, color: Colors.purple),
          ]),
          if (emergencies.isNotEmpty) ...[
            const SectionTitle('Emergency queue'),
            for (final e in emergencies) _EmergencyTile(e: e, onBack: reload),
          ],
          const SectionTitle('Blood stock by group (all facilities, unexpired)'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                for (final g in stock)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      SizedBox(width: 34, child: Text('${g['blood_group']}', style: const TextStyle(fontWeight: FontWeight.bold))),
                      Expanded(child: LinearProgressIndicator(value: (g['units'] as num) / maxUnits, minHeight: 10, borderRadius: BorderRadius.circular(5), color: (g['units'] as num) < 10 ? Colors.red.shade600 : Colors.green.shade600)),
                      SizedBox(width: 40, child: Text('${g['units']}', textAlign: TextAlign.right)),
                    ]),
                  ),
              ]),
            ),
          ),
          const SectionTitle('Requests by status'),
          Wrap(children: [for (final r in asList(s['requests_by_status'])) _stat(ctx, '${r['status']}', r['count'], Icons.assignment, color: statusColor(r['status'] as String))]),
          const SectionTitle('Donations (last months)'),
          Card(
            child: Column(children: [
              if (asList(s['donations_by_month']).isEmpty) const ListTile(title: Text('No donations yet')),
              for (final m in asList(s['donations_by_month'])) ListTile(dense: true, leading: const Icon(Icons.calendar_month), title: Text('${m['month']}'), trailing: Text('${m['donations']} donations • ${m['units']} units')),
            ]),
          ),
          const SizedBox(height: 30),
        ]);
      },
    );
  }
}

class _EmergencyTile extends StatelessWidget {
  const _EmergencyTile({required this.e, required this.onBack});
  final Map<String, dynamic> e;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final local = e['local_units'] as num;
    final canLocal = e['can_fulfil_locally'] == true;
    return Card(
      color: Colors.red.shade50,
      child: ListTile(
        leading: CircleAvatar(backgroundColor: statusColor(e['priority'] as String), child: Text('${e['blood_group']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
        title: Text('${e['units_needed']} unit(s) • ${e['patient_name']}'),
        subtitle: Text('${e['hospital_name']}\nThis hospital: $local u ${canLocal ? '✔ can fulfil' : '✖ short'} • Other facilities: ${e['network_units']} u'),
        isThreeLine: true,
        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [Pill(e['priority'] as String), const SizedBox(height: 4), Pill(e['status'] as String)]),
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => RequestDetailScreen(id: e['request_id'] as int)));
          onBack();
        },
      ),
    );
  }
}

// ---------------- Staff dashboard (emergency mode first) ----------------
class StaffDashboard extends StatelessWidget {
  const StaffDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return AsyncBody(
      load: () => Future.wait([
        Api.get('/requests/emergency'),
        Api.get('/inventory/hospital-stock'),
        Api.get('/requests', query: {'status': 'PENDING'}),
        Api.get('/inventory/batches'),
      ]),
      builder: (ctx, data, reload) {
        final parts = data as List<dynamic>;
        final emergencies = asList(parts[0]);
        final stock = asList(parts[1]);
        final pending = asList(parts[2]);
        final batches = asList(parts[3]);
        final expiring = batches.where((b) => (b['days_left'] as num) >= 0 && (b['days_left'] as num) <= 5 && b['status'] == 'AVAILABLE').length;
        return ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(8), children: [
          Padding(padding: const EdgeInsets.all(8), child: Text('${session.user!['hospital_name']}', style: Theme.of(ctx).textTheme.titleLarge)),
          Wrap(children: [
            _stat(ctx, 'Pending requests', pending.length, Icons.assignment_late, color: Colors.orange.shade800),
            _stat(ctx, 'Emergency / urgent', emergencies.length, Icons.emergency, color: Colors.red.shade700),
            _stat(ctx, 'Batches expiring ≤5d', expiring, Icons.timer, color: Colors.deepOrange),
          ]),
          SectionTitle('Emergency mode', trailing: emergencies.isEmpty ? null : Pill('${emergencies.length} OPEN', color: Colors.red.shade700)),
          if (emergencies.isEmpty) const Card(child: ListTile(leading: Icon(Icons.check_circle, color: Colors.green), title: Text('No urgent requests right now'))),
          for (final e in emergencies) _EmergencyTile(e: e, onBack: reload),
          const SectionTitle('Our stock (unexpired units)'),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final g in stock)
              Builder(builder: (_) {
                final u = int.tryParse('${g['units_available']}') ?? 0;
                final c = u == 0 ? Colors.red.shade700 : (u < 5 ? Colors.deepOrange : Colors.green.shade700);
                return Container(
                  width: 78,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(color: c.withAlpha(25), border: Border.all(color: c), borderRadius: BorderRadius.circular(10)),
                  child: Column(children: [Text('${g['blood_group']}', style: TextStyle(fontWeight: FontWeight.bold, color: c)), Text('$u u', style: TextStyle(fontSize: 18, color: c))]),
                );
              }),
          ]),
          const SizedBox(height: 30),
        ]);
      },
    );
  }
}

// ---------------- Audit logs & users ----------------
class AuditScreen extends StatelessWidget {
  const AuditScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return AsyncBody(
      load: () => Api.get('/admin/audit', query: {'limit': '150'}),
      builder: (ctx, data, reload) {
        final rows = asList(data);
        if (rows.isEmpty) return emptyList('No audit entries');
        return ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(8),
          itemCount: rows.length,
          itemBuilder: (_, i) {
            final a = rows[i];
            return Card(
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.history, size: 20),
                title: Text('${a['action']}'),
                subtitle: Text('${a['user_name'] ?? 'system'} • ${a['entity']}${a['entity_id'] != null ? ' #${a['entity_id']}' : ''}\n${a['details'] ?? ''}\n${a['created_at']}'),
                isThreeLine: true,
              ),
            );
          },
        );
      },
    );
  }
}

class UsersScreen extends StatelessWidget {
  const UsersScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return AsyncBody(
      load: () => Api.get('/admin/users'),
      builder: (ctx, data, reload) {
        final rows = asList(data);
        return ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(8),
          itemCount: rows.length,
          itemBuilder: (_, i) {
            final u = rows[i];
            return Card(
              child: ListTile(
                leading: CircleAvatar(child: Text((u['full_name'] as String).substring(0, 1))),
                title: Text('${u['full_name']}'),
                subtitle: Text('${u['email']}${u['hospital_name'] != null ? '\n${u['hospital_name']}' : ''}'),
                isThreeLine: u['hospital_name'] != null,
                trailing: Pill('${u['role']}', color: Colors.blueGrey),
              ),
            );
          },
        );
      },
    );
  }
}
