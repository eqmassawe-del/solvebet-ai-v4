import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/theme.dart';
import '../state/providers.dart';
import 'screens/builder_screen.dart';
import 'screens/capital_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/performance_lab_screen.dart';
import 'screens/scanner_screen.dart';
import 'screens/selections_screen.dart';
import 'screens/settings_screen.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});
  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  void go(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final pages = [
      DashboardScreen(onNavigate: go),
      const ScannerScreen(),
      const SelectionsScreen(),
      const BuilderScreen(),
      const CapitalScreen(),
    ];
    final titles = [s.t('dashboard'), s.t('scanner'), s.t('selections'), s.t('builder'), s.t('capital')];
    return Scaffold(
      appBar: AppBar(
        title: Text(_index == 0 ? 'MATHematics BET AI' : titles[_index].toUpperCase()),
        actions: [
          IconButton(
            tooltip: s.t('settings'),
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      drawer: Drawer(
        backgroundColor: AppColors.graphite,
        child: SafeArea(
          child: ListView(children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 20, 16, 4),
              child: Text("KING'S VISA", style: TextStyle(color: AppColors.gold, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 2)),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text('Evidence → Failure analysis → Risk → VISA → Optimisation → Capital control',
                  style: TextStyle(color: AppColors.muted, fontSize: 11)),
            ),
            for (var i = 0; i < titles.length; i++)
              ListTile(
                selected: _index == i,
                leading: Icon(_icons[i]),
                title: Text(titles[i]),
                onTap: () {
                  Navigator.pop(context);
                  go(i);
                },
              ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.science_outlined),
              title: Text(s.t('lab')),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const PerformanceLabScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: Text(s.t('settings')),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
              },
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(s.t('disclaimer'), style: const TextStyle(color: AppColors.muted, fontSize: 11)),
            ),
          ]),
        ),
      ),
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: go,
        destinations: [
          for (var i = 0; i < titles.length; i++)
            NavigationDestination(icon: Icon(_icons[i]), label: titles[i].split(' ').last),
        ],
      ),
    );
  }

  static const _icons = [
    Icons.dashboard_outlined,
    Icons.radar,
    Icons.fact_check_outlined,
    Icons.account_tree_outlined,
    Icons.account_balance_wallet_outlined,
  ];
}
