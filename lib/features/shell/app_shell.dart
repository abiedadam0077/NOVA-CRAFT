import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../../design/theme.dart';
import '../../design/widgets/background.dart';
import '../../design/widgets/nav.dart';
import '../console/console_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../files/files_screen.dart';
import '../servers/servers_screen.dart';
import '../settings/settings_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  void _select(int index) {
    if (index == _index) return;
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return Scaffold(
      extendBody: true,
      backgroundColor: p.bg,
      body: AuroraBackground(
        child: IndexedStack(
          index: _index,
          children: <Widget>[
            DashboardScreen(active: _index == 0, onOpenServers: () => _select(1)),
            ServersScreen(active: _index == 1),
            ConsoleScreen(active: _index == 2, onPickServer: () => _select(1)),
            FilesScreen(active: _index == 3, onPickServer: () => _select(1)),
            SettingsScreen(active: _index == 4),
          ],
        ),
      ),
      bottomNavigationBar: NovaBottomBar(
        index: _index,
        onChanged: _select,
        items: <NovaNavItem>[
          NovaNavItem(label: L10n.t('navHome'), icon: Icons.space_dashboard_outlined, activeIcon: Icons.space_dashboard_rounded),
          NovaNavItem(label: L10n.t('navServers'), icon: Icons.dns_outlined, activeIcon: Icons.dns_rounded),
          NovaNavItem(label: L10n.t('navConsole'), icon: Icons.terminal_outlined, activeIcon: Icons.terminal_rounded),
          NovaNavItem(label: L10n.t('navFiles'), icon: Icons.folder_copy_outlined, activeIcon: Icons.folder_copy_rounded),
          NovaNavItem(label: L10n.t('navSettings'), icon: Icons.settings_outlined, activeIcon: Icons.settings_rounded),
        ],
      ),
    );
  }
}
