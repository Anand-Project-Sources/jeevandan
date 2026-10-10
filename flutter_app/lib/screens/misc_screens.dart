import 'package:flutter/material.dart';
import '../services/api.dart';
import '../widgets.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  int _rev = 0;

  IconData _icon(String t) {
    switch (t) {
      case 'REQUEST':
        return Icons.bloodtype;
      case 'LOW_STOCK':
        return Icons.warning_amber;
      case 'EXPIRY':
        return Icons.timer_off;
      case 'TRANSFER':
        return Icons.swap_horiz;
      case 'DONOR_MATCH':
        return Icons.volunteer_activism;
      case 'ORGAN':
        return Icons.favorite;
      default:
        return Icons.notifications;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.small(
        tooltip: 'Mark all read',
        onPressed: () async {
          await doAction(context, () => Api.post('/notifications/read-all'));
          if (mounted) setState(() { _rev++; });
        },
        child: const Icon(Icons.done_all),
      ),
      body: AsyncBody(
        key: ValueKey(_rev),
        load: () => Api.get('/notifications'),
        builder: (ctx, data, reload) {
          final rows = asList(data);
          if (rows.isEmpty) return emptyList('No notifications');
          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 80),
            itemCount: rows.length,
            itemBuilder: (_, i) {
              final n = rows[i];
              final unread = !truthy(n['is_read']);
              return Card(
                color: unread ? Colors.red.shade50 : null,
                child: ListTile(
                  leading: Icon(_icon(n['type'] as String), color: unread ? Colors.red.shade700 : Colors.grey),
                  title: Text('${n['title']}', style: TextStyle(fontWeight: unread ? FontWeight.bold : FontWeight.normal)),
                  subtitle: Text('${n['message']}\n${n['created_at']}'),
                  isThreeLine: true,
                  onTap: unread
                      ? () async {
                          await Api.post('/notifications/${n['notification_id']}/read');
                          reload();
                        }
                      : null,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _city;
  late final TextEditingController _weight;
  final _cur = TextEditingController();
  final _new = TextEditingController();
  bool _busy = false;

  Map<String, dynamic>? get _donor => session.user?['donor'] == null ? null : asMap(session.user!['donor']);

  @override
  void initState() {
    super.initState();
    final u = session.user!;
    _name = TextEditingController(text: u['full_name'] as String);
    _phone = TextEditingController(text: u['phone'] as String);
    _city = TextEditingController(text: _donor?['city']?.toString() ?? '');
    _weight = TextEditingController(text: _donor?['weight_kg']?.toString() ?? '');
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() { _busy = true; });
    final body = <String, dynamic>{'full_name': _name.text.trim(), 'phone': _phone.text.trim()};
    if (_donor != null) body['donor'] = {'city': _city.text.trim(), 'weight_kg': double.tryParse(_weight.text.trim())};
    if (_new.text.isNotEmpty) {
      body['current_password'] = _cur.text;
      body['new_password'] = _new.text;
    }
    final ok = await doAction(context, () => Api.put('/me', body), ok: 'Profile updated');
    if (ok) {
      try { await session.refreshProfile(); } catch (_) {}
      _cur.clear();
      _new.clear();
    }
    if (mounted) setState(() { _busy = false; });
  }

  @override
  Widget build(BuildContext context) {
    final u = session.user!;
    return Form(
      key: _form,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.email), title: Text('${u['email']}'), subtitle: Text('Role: ${u['role']}${u['hospital_name'] != null ? ' • ${u['hospital_name']}' : ''}')),
        if (_donor != null) ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.bloodtype), title: Text('Blood group ${_donor!['blood_group']}'), subtitle: const Text('Blood group cannot be changed. Contact an admin if it was entered wrongly.')),
        const SizedBox(height: 8),
        TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Full name'), validator: (v) => (v == null || v.trim().length < 2) ? 'Enter your name' : null),
        const SizedBox(height: 12),
        TextFormField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone'), validator: (v) => (v == null || !RegExp(r'^\+?[0-9]{10,13}$').hasMatch(v.replaceAll(RegExp(r'[\s-]'), ''))) ? 'Enter a valid phone number' : null),
        if (_donor != null) ...[
          const SizedBox(height: 12),
          TextFormField(controller: _city, decoration: const InputDecoration(labelText: 'City'), validator: (v) => (v == null || v.trim().length < 2) ? 'Enter your city' : null),
          const SizedBox(height: 12),
          TextFormField(controller: _weight, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Weight (kg)'), validator: (v) { final w = double.tryParse(v ?? ''); return (w == null || w < 30 || w > 250) ? 'Enter a valid weight' : null; }),
        ],
        const SectionTitle('Change password (optional)'),
        TextFormField(controller: _cur, obscureText: true, decoration: const InputDecoration(labelText: 'Current password')),
        const SizedBox(height: 12),
        TextFormField(
          controller: _new,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'New password'),
          validator: (v) => (v != null && v.isNotEmpty && (v.length < 8 || !RegExp(r'[A-Za-z]').hasMatch(v) || !RegExp(r'[0-9]').hasMatch(v))) ? 'Min 8 characters with a letter and a digit' : null,
        ),
        const SizedBox(height: 20),
        SizedBox(height: 48, child: FilledButton(onPressed: _busy ? null : _save, child: _busy ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save changes'))),
      ]),
    );
  }
}
