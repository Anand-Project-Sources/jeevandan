import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api.dart';
import 'admin_screens.dart';
import 'donor_screens.dart';
import 'inventory_screens.dart';
import 'misc_screens.dart';
import 'organ_screens.dart';
import 'request_screens.dart';
import 'transfer_screens.dart';

class _Dest {
  final String label;
  final IconData icon;
  final WidgetBuilder build;
  _Dest(this.label, this.icon, this.build);
}

List<_Dest> _destinationsFor(String role) {
  final notif = _Dest('Notifications', Icons.notifications, (_) => const NotificationsScreen());
  final profile = _Dest('Profile', Icons.person, (_) => const ProfileScreen());
  switch (role) {
    case 'ADMIN':
      return [
        _Dest('Dashboard', Icons.dashboard, (_) => const AdminDashboard()),
        _Dest('Blood Requests', Icons.bloodtype, (_) => const RequestListScreen()),
        _Dest('Blood Stock', Icons.inventory_2, (_) => const InventorySearchScreen()),
        _Dest('Transfers', Icons.swap_horiz, (_) => const TransferListScreen()),
        _Dest('Organ Requests', Icons.favorite, (_) => const OrganRequestListScreen()),
        _Dest('Users', Icons.people, (_) => const UsersScreen()),
        _Dest('Audit Logs', Icons.history, (_) => const AuditScreen()),
        notif,
        profile,
      ];
    case 'STAFF':
      return [
        _Dest('Dashboard', Icons.dashboard, (_) => const StaffDashboard()),
        _Dest('Blood Requests', Icons.bloodtype, (_) => const RequestListScreen()),
        _Dest('Our Inventory', Icons.inventory_2, (_) => const BatchesScreen()),
        _Dest('Find Stock', Icons.search, (_) => const InventorySearchScreen()),
        _Dest('Donors', Icons.volunteer_activism, (_) => const DonorsScreen()),
        _Dest('Transfers', Icons.swap_horiz, (_) => const TransferListScreen()),
        _Dest('Organ Requests', Icons.favorite, (_) => const OrganRequestListScreen()),
        notif,
        profile,
      ];
    case 'DONOR':
      return [
        _Dest('My Donor Home', Icons.home, (_) => const DonorHome()),
        _Dest('Find Blood', Icons.search, (_) => const InventorySearchScreen()),
        _Dest('Organ Pledge', Icons.favorite, (_) => const OrganConsentScreen()),
        notif,
        profile,
      ];
    default:
      return [
        _Dest('Find Blood', Icons.search, (_) => const InventorySearchScreen()),
        _Dest('My Requests', Icons.bloodtype, (_) => const RequestListScreen()),
        notif,
        profile,
      ];
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _i = 0;
  int _unread = 0;
  Timer? _timer;
  late final List<_Dest> _dests;

  @override
  void initState() {
    super.initState();
    _dests = _destinationsFor(session.role);
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    try {
      final d = await Api.get('/notifications/unread-count');
      if (mounted) {
        setState(() {
          _unread = (d['count'] as num).toInt();
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final u = session.user!;
    final bellIndex = _dests.indexWhere((d) => d.label == 'Notifications');
    return Scaffold(
      appBar: AppBar(
        title: Text(_dests[_i].label),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            onPressed: () {
              setState(() {
                _i = bellIndex;
              });
              _poll();
            },
            icon: Badge(isLabelVisible: _unread > 0, label: Text('$_unread'), child: const Icon(Icons.notifications_outlined)),
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(padding: EdgeInsets.zero, children: [
          UserAccountsDrawerHeader(
            accountName: Text(u['full_name'] as String),
            accountEmail: Text('${session.role}${u['hospital_name'] != null ? ' • ${u['hospital_name']}' : ''}'),
            currentAccountPicture: CircleAvatar(
              backgroundColor: Colors.white,
              child: Text((u['full_name'] as String).substring(0, 1).toUpperCase(), style: TextStyle(fontSize: 28, color: Theme.of(context).colorScheme.primary)),
            ),
          ),
          for (var k = 0; k < _dests.length; k++)
            ListTile(
              selected: k == _i,
              leading: Icon(_dests[k].icon),
              title: Text(_dests[k].label),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _i = k;
                });
                _poll();
              },
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Logout'),
            onTap: () async {
              Navigator.pop(context);
              await session.logout();
            },
          ),
        ]),
      ),
      body: KeyedSubtree(key: ValueKey('dest-$_i'), child: _dests[_i].build(context)),
    );
  }
}
