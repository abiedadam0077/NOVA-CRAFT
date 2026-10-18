import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/strings.dart';
import '../../design/theme.dart';
import '../../design/tokens.dart';
import '../../design/widgets/background.dart';
import '../../design/widgets/brand.dart';
import '../../design/widgets/buttons.dart';
import '../../design/widgets/display.dart';
import '../../design/widgets/nav.dart';
import '../../design/widgets/surfaces.dart';
import '../../state/app_state.dart';
import '../console/console_screen.dart';
import '../files/files_screen.dart';
import '../home/home_screen.dart';
import '../mods/bedrock_addons.dart';
import '../mods/mods_screen.dart';
import '../servers/create_server_screen.dart';
import '../settings/server_settings_screen.dart';

/// The five-destination shell. There is deliberately no sixth tab: servers,
/// backups, worlds, network and app preferences are reached from Home or
/// Server settings.
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

  Future<void> _openServerPicker() async {
    final AppState state = AppScope.read(context);
    final ServerConfig? picked = await showModalBottomSheet<ServerConfig>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext context) => _ServerPicker(
        servers: state.servers,
        selected: state.selected,
      ),
    );
    if (picked != null) {
      state.selectServer(picked);
      _select(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    final AppState state = AppScope.of(context);
    if (state.selected == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      extendBody: true,
      backgroundColor: p.bg,
      body: AuroraBackground(
        child: IndexedStack(
          index: _index,
          children: <Widget>[
            HomeScreen(active: _index == 0, onPickServer: _openServerPicker),
            ConsoleScreen(active: _index == 1, onPickServer: _openServerPicker),
            FilesScreen(active: _index == 2, onPickServer: _openServerPicker),
            _ModsTab(active: _index == 3),
            ServerSettingsScreen(active: _index == 4),
          ],
        ),
      ),
      bottomNavigationBar: NovaBottomBar(
        index: _index,
        onChanged: _select,
        items: <NovaNavItem>[
          NovaNavItem(label: L10n.t('navHome'), icon: Icons.space_dashboard_outlined, activeIcon: Icons.space_dashboard_rounded),
          NovaNavItem(label: L10n.t('navConsole'), icon: Icons.terminal_outlined, activeIcon: Icons.terminal_rounded),
          NovaNavItem(label: L10n.t('navFiles'), icon: Icons.folder_copy_outlined, activeIcon: Icons.folder_copy_rounded),
          NovaNavItem(label: L10n.t('navMods'), icon: Icons.extension_outlined, activeIcon: Icons.extension_rounded),
          NovaNavItem(label: L10n.t('navServerSettings'), icon: Icons.tune_outlined, activeIcon: Icons.tune_rounded),
        ],
      ),
    );
  }
}

class _ModsTab extends StatelessWidget {
  const _ModsTab({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final ServerConfig? server = AppScope.of(context).selected;
    if (server == null) {
      return const SizedBox.shrink();
    }
    return SafeArea(
      bottom: false,
      child: server.isBedrock
          ? BedrockAddonsView(config: server, active: active)
          : ModsView(config: server, active: active),
    );
  }
}

class _ServerPicker extends StatelessWidget {
  const _ServerPicker({required this.servers, required this.selected});

  final List<ServerConfig> servers;
  final ServerConfig? selected;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
      decoration: BoxDecoration(
        color: p.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(NovaRadii.xxl)),
        border: Border.all(color: p.stroke),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: 10),
            Container(width: 42, height: 4, decoration: BoxDecoration(color: p.textDim, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: <Widget>[
                  Expanded(child: Text(L10n.t('homeServerSwitcher'), style: NovaTextStyles.heading(18, p.text))),
                  const BrandLockup(markSize: 24, fontSize: 12, letterSpacing: 1.6),
                ],
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: servers.length,
                itemBuilder: (BuildContext context, int index) {
                  final ServerConfig server = servers[index];
                  final bool active = selected?.repoFull == server.repoFull;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: PressableScale(
                      onTap: () => Navigator.of(context).pop(server),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: active ? p.primary.withValues(alpha: 0.12) : p.cardSoft,
                          borderRadius: NovaRadii.rMd,
                          border: Border.all(color: active ? p.primary.withValues(alpha: 0.45) : p.stroke),
                        ),
                        child: Row(
                          children: <Widget>[
                            ServerAvatar(name: server.name, edition: server.edition, software: server.software, size: 42),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(server.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: NovaTextStyles.title(p.text)),
                                  Text('${server.mcVersion} · ${server.softwareLabel}', style: NovaTextStyles.caption(p.textDim)),
                                ],
                              ),
                            ),
                            if (active) Icon(Icons.check_circle_rounded, color: p.successBright, size: 20),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: NovaButton(
                label: L10n.t('createServer'),
                icon: Icons.add_rounded,
                variant: NovaButtonVariant.secondary,
                height: 48,
                size: NovaButtonSize.compact,
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CreateServerScreen()));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
