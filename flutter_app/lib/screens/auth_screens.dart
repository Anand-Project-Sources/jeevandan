import 'package:flutter/material.dart';
import '../services/api.dart';
import '../widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _pw = TextEditingController();
  bool _busy = false;
  bool _hide = true;

  static const _demo = [
    ['Admin', 'admin@jeevandan.test'],
    ['Hospital staff (Narmada Care)', 'staff1@jeevandan.test'],
    ['Blood bank staff (Sanjeevani)', 'staff2@jeevandan.test'],
    ['Donor (O-)', 'donor1@jeevandan.test'],
    ['Patient', 'patient1@jeevandan.test'],
  ];

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
    });
    try {
      await session.login(_email.text.trim(), _pw.text);
    } catch (e) {
      if (mounted) snack(context, errText(e), error: true);
    }
    if (mounted) {
      setState(() {
        _busy = false;
      });
    }
  }

  Future<void> _serverDialog() async {
    final ctrl = TextEditingController(text: Api.baseUrl);
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Server URL'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Emulator: http://10.0.2.2:3000\nReal phone: http://<your-PC-IP>:3000', style: TextStyle(fontSize: 12)),
          const SizedBox(height: 12),
          TextField(controller: ctrl, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Backend URL')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Save')),
        ],
      ),
    );
    if (url != null && url.trim().startsWith('http')) {
      await session.setServerUrl(url);
      if (mounted) snack(context, 'Server set to ${Api.baseUrl}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: Column(children: [
                  Align(alignment: Alignment.centerRight, child: IconButton(icon: const Icon(Icons.settings), tooltip: 'Server URL', onPressed: _serverDialog)),
                  Icon(Icons.bloodtype, size: 72, color: cs.primary),
                  const SizedBox(height: 8),
                  Text('JEEVANDAN', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold, color: cs.primary)),
                  const Text('Blood & Organ Donation Management'),
                  const SizedBox(height: 28),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
                    validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _pw,
                    obscureText: _hide,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(icon: Icon(_hide ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() { _hide = !_hide; })),
                    ),
                    validator: (v) => (v == null || v.isEmpty) ? 'Enter your password' : null,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Login'),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RegisterScreen())),
                    child: const Text('New here? Register as donor / patient'),
                  ),
                  const SizedBox(height: 8),
                  ExpansionTile(
                    title: const Text('Demo accounts', style: TextStyle(fontSize: 14)),
                    subtitle: const Text('Password for all: Demo@1234', style: TextStyle(fontSize: 12)),
                    children: [
                      for (final d in _demo)
                        ListTile(
                          dense: true,
                          title: Text(d[0]),
                          subtitle: Text(d[1]),
                          onTap: () {
                            _email.text = d[1];
                            _pw.text = 'Demo@1234';
                          },
                        ),
                    ],
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  String _role = 'DONOR';
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _pw = TextEditingController();
  final _city = TextEditingController();
  final _weight = TextEditingController();
  String? _bg;
  String _gender = 'M';
  DateTime? _dob;
  bool _busy = false;

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 25),
      firstDate: DateTime(now.year - 70),
      lastDate: DateTime(now.year - 18, now.month, now.day),
    );
    if (d != null) {
      setState(() {
        _dob = d;
      });
    }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (_role == 'DONOR' && _dob == null) {
      snack(context, 'Select your date of birth', error: true);
      return;
    }
    setState(() {
      _busy = true;
    });
    final body = <String, dynamic>{
      'role': _role,
      'full_name': _name.text.trim(),
      'email': _email.text.trim(),
      'phone': _phone.text.trim(),
      'password': _pw.text,
    };
    if (_role == 'DONOR') {
      body.addAll({
        'blood_group': _bg,
        'date_of_birth': _dob!.toIso8601String().substring(0, 10),
        'gender': _gender,
        'weight_kg': double.tryParse(_weight.text.trim()),
        'city': _city.text.trim(),
      });
    }
    try {
      await session.register(body);
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (mounted) {
        snack(context, errText(e), error: true);
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: Lookups.get(),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) return ErrorView(message: errText(snap.error), onRetry: () => setState(() {}));
          final groups = asList(snap.data!['bloodGroups']);
          return Form(
            key: _form,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'DONOR', label: Text('Donor'), icon: Icon(Icons.volunteer_activism)),
                  ButtonSegment(value: 'PATIENT', label: Text('Patient / Requester'), icon: Icon(Icons.personal_injury)),
                ],
                selected: {_role},
                onSelectionChanged: (s) => setState(() {
                  _role = s.first;
                }),
              ),
              const SizedBox(height: 16),
              TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Full name'), validator: (v) => (v == null || v.trim().length < 2) ? 'Enter your name' : null),
              const SizedBox(height: 12),
              TextFormField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email'), validator: (v) => (v == null || !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$').hasMatch(v.trim())) ? 'Enter a valid email' : null),
              const SizedBox(height: 12),
              TextFormField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone (10-13 digits)'), validator: (v) => (v == null || !RegExp(r'^\+?[0-9]{10,13}$').hasMatch(v.replaceAll(RegExp(r'[\s-]'), ''))) ? 'Enter a valid phone number' : null),
              const SizedBox(height: 12),
              TextFormField(controller: _pw, obscureText: true, decoration: const InputDecoration(labelText: 'Password (8+ chars, letter & digit)'), validator: (v) => (v == null || v.length < 8 || !RegExp(r'[A-Za-z]').hasMatch(v) || !RegExp(r'[0-9]').hasMatch(v)) ? 'Min 8 characters with a letter and a digit' : null),
              if (_role == 'DONOR') ...[
                const SizedBox(height: 12),
                BloodGroupField(groups: groups, value: _bg, onChanged: (v) => setState(() {
                      _bg = v;
                    })),
                const SizedBox(height: 12),
                ListTile(
                  shape: RoundedRectangleBorder(side: const BorderSide(color: Colors.grey), borderRadius: BorderRadius.circular(4)),
                  title: Text(_dob == null ? 'Date of birth (18-65)' : _dob!.toIso8601String().substring(0, 10)),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: _pickDob,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _gender,
                  decoration: const InputDecoration(labelText: 'Gender'),
                  items: const [
                    DropdownMenuItem(value: 'M', child: Text('Male')),
                    DropdownMenuItem(value: 'F', child: Text('Female')),
                    DropdownMenuItem(value: 'O', child: Text('Other')),
                  ],
                  onChanged: (v) => setState(() {
                    _gender = v ?? 'M';
                  }),
                ),
                const SizedBox(height: 12),
                TextFormField(controller: _weight, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Weight (kg, min 45)'), validator: (v) { final w = double.tryParse(v ?? ''); return (w == null || w < 45 || w > 250) ? 'Donors must weigh at least 45 kg' : null; }),
                const SizedBox(height: 12),
                TextFormField(controller: _city, decoration: const InputDecoration(labelText: 'City'), validator: (v) => (v == null || v.trim().length < 2) ? 'Enter your city' : null),
              ],
              const SizedBox(height: 24),
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Register'),
                ),
              ),
            ]),
          );
        },
      ),
    );
  }
}
