import 'package:flutter/material.dart';
import 'services/api.dart';

bool truthy(dynamic v) => v == true || v == 1 || v == '1';

List<Map<String, dynamic>> asList(dynamic d) =>
    (d as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

Map<String, dynamic> asMap(dynamic d) => Map<String, dynamic>.from(d as Map);

void snack(BuildContext c, String m, {bool error = false}) {
  ScaffoldMessenger.of(c)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(m),
      backgroundColor: error ? Colors.red.shade700 : null,
      behavior: SnackBarBehavior.floating,
    ));
}

Future<bool> confirmDialog(BuildContext c, String title, String msg) async {
  final r = await showDialog<bool>(
    context: c,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: Text(msg),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Confirm')),
      ],
    ),
  );
  return r == true;
}

Future<String?> textPrompt(BuildContext c, String title, {String hint = '', int minLen = 3}) async {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: c,
    builder: (_) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          decoration: InputDecoration(hintText: hint),
          onChanged: (_) => setS(() {}),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: ctrl.text.trim().length >= minLen ? () => Navigator.pop(ctx, ctrl.text.trim()) : null,
            child: const Text('Submit'),
          ),
        ],
      ),
    ),
  );
}

/// Runs an API action, shows success/error snackbar, returns whether it succeeded.
Future<bool> doAction(BuildContext c, Future<dynamic> Function() fn, {String? ok}) async {
  try {
    await fn();
    if (c.mounted && ok != null) snack(c, ok);
    return true;
  } catch (e) {
    if (c.mounted) snack(c, errText(e), error: true);
    return false;
  }
}

Color statusColor(String s) {
  switch (s.toUpperCase()) {
    case 'PENDING':
    case 'UNDER_REVIEW':
    case 'NOTIFIED':
      return Colors.orange.shade800;
    case 'APPROVED':
    case 'VERIFIED':
      return Colors.blue.shade700;
    case 'FULFILLED':
    case 'COMPLETED':
    case 'ACCEPTED':
    case 'GIVEN':
    case 'AVAILABLE':
      return Colors.green.shade700;
    case 'REJECTED':
    case 'CANCELLED':
    case 'DECLINED':
    case 'EXPIRED':
    case 'WITHDRAWN':
    case 'EMERGENCY':
    case 'CRITICAL':
      return Colors.red.shade700;
    case 'URGENT':
      return Colors.deepOrange;
    default:
      return Colors.blueGrey;
  }
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color});
  final String text;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final c = color ?? statusColor(text);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: c.withAlpha(30),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c),
      ),
      child: Text(text.replaceAll('_', ' '),
          style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 8, 6),
        child: Row(children: [
          Expanded(child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
          if (trailing != null) trailing!,
        ]),
      );
}

class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 110, child: Text(label, style: const TextStyle(color: Colors.grey))),
          Expanded(child: Text(value)),
        ]),
      );
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
            ],
          ]),
        ),
      );
}

/// A scrollable empty state (keeps pull-to-refresh working).
Widget emptyList(String msg) => ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Center(child: Text(msg, style: const TextStyle(color: Colors.grey))),
      ],
    );

/// Loads data, shows spinner/error, supports pull-to-refresh. Builder must return a scrollable.
class AsyncBody extends StatefulWidget {
  const AsyncBody({super.key, required this.load, required this.builder});
  final Future<dynamic> Function() load;
  final Widget Function(BuildContext context, dynamic data, VoidCallback reload) builder;
  @override
  State<AsyncBody> createState() => _AsyncBodyState();
}

class _AsyncBodyState extends State<AsyncBody> {
  late Future<dynamic> _f;

  @override
  void initState() {
    super.initState();
    _f = widget.load();
  }

  void _reload() {
    setState(() {
      _f = widget.load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<dynamic>(
      future: _f,
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) return ErrorView(message: errText(snap.error), onRetry: _reload);
        return RefreshIndicator(
          onRefresh: () async {
            _reload();
            try {
              await _f;
            } catch (_) {}
          },
          child: widget.builder(ctx, snap.data, _reload),
        );
      },
    );
  }
}

/// Loading-aware blood group dropdown.
class BloodGroupField extends StatelessWidget {
  const BloodGroupField({super.key, required this.groups, required this.value, required this.onChanged, this.label = 'Blood group', this.allowAny = false});
  final List<Map<String, dynamic>> groups;
  final String? value;
  final ValueChanged<String?> onChanged;
  final String label;
  final bool allowAny;
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
        value: value,
        decoration: InputDecoration(labelText: label),
        items: [
          if (allowAny) const DropdownMenuItem<String>(value: null, child: Text('Any')),
          for (final g in groups) DropdownMenuItem<String>(value: g['label'] as String, child: Text(g['label'] as String)),
        ],
        validator: allowAny ? null : (v) => v == null ? 'Select a blood group' : null,
        onChanged: onChanged,
      );
}
