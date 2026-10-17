import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models.dart';
import '../../core/strings.dart';
import '../../design/theme.dart';
import '../../design/tokens.dart';
import '../../design/widgets/buttons.dart';
import '../../design/widgets/display.dart';
import '../../design/widgets/feedback.dart';
import '../../design/widgets/inputs.dart';
import '../../design/widgets/surfaces.dart';
import '../../state/app_state.dart';
import '../../state/monitor_scope.dart';
import '../../state/server_monitor.dart';
import 'create_server_screen.dart';
import 'server_detail_screen.dart';

class ServersScreen extends StatefulWidget {
  const ServersScreen({super.key, required this.active});

  final bool active;

  @override
  State<ServersScreen> createState() => _ServersScreenState();
}

class _ServersScreenState extends State<ServersScreen> {
  final TextEditingController _search = TextEditingController();
  String _filter = 'all';
  String _sort = 'name';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<ServerConfig> _visible(List<ServerConfig> servers, Map<String, ServerPhase> phases) {
    final String q = _search.text.trim().toLowerCase();
    final List<ServerConfig> out = servers.where((ServerConfig s) {
      if (q.isNotEmpty) {
        final bool matches = s.name.toLowerCase().contains(q) ||
            s.mcVersion.toLowerCase().contains(q) ||
            s.software.toLowerCase().contains(q) ||
            s.repoFull.toLowerCase().contains(q);
        if (!matches) return false;
      }
      switch (_filter) {
        case 'java':
          return s.isJava;
        case 'bedrock':
          return s.isBedrock;
        case 'online':
          return phases[s.repoFull] == ServerPhase.online;
        case 'offline':
          return phases[s.repoFull] == ServerPhase.offline || phases[s.repoFull] == ServerPhase.unknown;
        default:
          return true;
      }
    }).toList();
    out.sort((ServerConfig a, ServerConfig b) {
      if (_sort == 'status') {
        final int rankA = phases[a.repoFull] == ServerPhase.online ? 0 : 1;
        final int rankB = phases[b.repoFull] == ServerPhase.online ? 0 : 1;
        if (rankA != rankB) return rankA - rankB;
      }
      if (_sort == 'recent') return b.createdAt.compareTo(a.createdAt);
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = AppScope.of(context);
    final p = context.nova;
    final Map<String, ServerPhase> phases = <String, ServerPhase>{};
    final List<ServerConfig> visible = _visible(state.servers, phases);

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: p.primaryBright,
        backgroundColor: p.cardHigh,
        onRefresh: state.refreshServers,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: const EdgeInsets.fromLTRB(NovaSpace.page, 10, NovaSpace.page, 130),
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(L10n.t('myServers'), style: NovaTextStyles.display(27, p.text)),
                      const SizedBox(height: 3),
                      Text(
                        '${L10n.t('serversSubtitle')} · ${state.servers.length}',
                        style: NovaTextStyles.small(p.textMuted),
                      ),
                    ],
                  ),
                ),
                NovaButton(
                  label: L10n.t('addServer'),
                  icon: Icons.add_rounded,
                  size: NovaButtonSize.compact,
                  expand: false,
                  variant: NovaButtonVariant.secondary,
                  onPressed: () => _openCreate(context),
                ),
              ],
            ),
            const SizedBox(height: 16),
            NovaSearchField(
              controller: _search,
              hint: L10n.t('searchServers'),
              onChanged: (_) => setState(() {}),
              onClear: () => setState(() => _search.clear()),
              trailing: PopupMenuButton<String>(
                tooltip: L10n.t('sortBy'),
                icon: Icon(Icons.swap_vert_rounded, size: 18, color: p.textMuted),
                color: p.cardHigh,
                initialValue: _sort,
                onSelected: (String value) => setState(() => _sort = value),
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(value: 'name', child: Text(L10n.t('sortName'))),
                  PopupMenuItem<String>(value: 'recent', child: Text(L10n.t('sortRecent'))),
                  PopupMenuItem<String>(value: 'status', child: Text(L10n.t('sortStatus'))),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: <Widget>[
                  NovaChip(label: L10n.t('filterAll'), selected: _filter == 'all', onTap: () => setState(() => _filter = 'all')),
                  const SizedBox(width: 8),
                  NovaChip(label: L10n.t('filterJava'), selected: _filter == 'java', onTap: () => setState(() => _filter = 'java')),
                  const SizedBox(width: 8),
                  NovaChip(label: L10n.t('filterBedrock'), selected: _filter == 'bedrock', onTap: () => setState(() => _filter = 'bedrock')),
                  const SizedBox(width: 8),
                  NovaChip(label: L10n.t('filterOnline'), selected: _filter == 'online', onTap: () => setState(() => _filter = 'online')),
                  const SizedBox(width: 8),
                  NovaChip(label: L10n.t('filterOffline'), selected: _filter == 'offline', onTap: () => setState(() => _filter = 'offline')),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (state.loadingServers && state.servers.isEmpty)
              const SkeletonList(count: 3, cardHeight: 118)
            else if (state.serversError != null && state.servers.isEmpty)
              ErrorState(
                message: state.serversError!,
                onRetry: state.refreshServers,
              )
            else if (visible.isEmpty)
              EmptyState(
                title: state.servers.isEmpty ? L10n.t('emptyServersTitle') : L10n.t('noResults'),
                body: state.servers.isEmpty ? L10n.t('emptyServersBody') : L10n.t('noServersFiltered'),
                icon: Icons.dns_rounded,
                artAsset: 'assets/images/art_island.jpg',
                actionLabel: L10n.t('createServer'),
                onAction: () => _openCreate(context),
              )
            else
              ...visible.map((ServerConfig server) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: MonitorScope(
                      config: server,
                      active: widget.active,
                      interval: const Duration(seconds: 45),
                      builder: (BuildContext context, ServerMonitor monitor) {
                        return ServerCard(
                          server: server,
                          phase: monitor.phase,
                          playersOnline: monitor.playersOnline,
                          playersMax: monitor.playersMax,
                          selected: state.selected?.repoFull == server.repoFull,
                          onTap: () => _openDetail(context, server),
                          onMenu: () => _serverMenu(context, server, monitor),
                        );
                      },
                    ),
                  )),
            if (state.servers.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              NovaCard(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.shield_moon_rounded, size: 18, color: p.textDim),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        L10n.t('githubRunnersNote'),
                        style: NovaTextStyles.small(p.textDim),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _openCreate(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CreateServerScreen()));
  }

  void _openDetail(BuildContext context, ServerConfig server) {
    final AppState state = AppScope.read(context);
    state.selectServer(server);
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ServerDetailScreen(config: server),
    ));
  }

  Future<void> _serverMenu(BuildContext context, ServerConfig server, ServerMonitor monitor) async {
    final AppState state = AppScope.read(context);
    final p = context.nova;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) {
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            border: Border(top: BorderSide(color: p.stroke)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(color: p.strokeStrong, borderRadius: NovaRadii.rPill),
              ),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  ServerAvatar(name: server.name, size: 42, edition: server.edition, software: server.software, online: monitor.phase == ServerPhase.online),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(server.name, style: NovaTextStyles.title(p.text)),
                        Text(server.repoFull, style: NovaTextStyles.small(p.textDim)),
                      ],
                    ),
                  ),
                  StatusPill(phase: monitor.phase, dense: true),
                ],
              ),
              const SizedBox(height: 14),
              SoftDivider(),
              _MenuTile(
                icon: Icons.open_in_new_rounded,
                label: L10n.t('openServer'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _openDetail(context, server);
                },
              ),
              _MenuTile(
                icon: Icons.terminal_rounded,
                label: L10n.t('tabConsole'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  state.selectServer(server);
                  Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => ServerDetailScreen(config: server, initialTab: 1),
                  ));
                },
              ),
              _MenuTile(
                icon: Icons.folder_copy_rounded,
                label: L10n.t('tabFiles'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  state.selectServer(server);
                  Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => ServerDetailScreen(config: server, initialTab: 2),
                  ));
                },
              ),
              _MenuTile(
                icon: Icons.content_copy_rounded,
                label: L10n.t('copyRepoUrl'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  Clipboard.setData(ClipboardData(text: 'https://github.com/${server.repoFull}'));
                  showNovaToast(context, L10n.t('copied'), kind: ToastKind.success);
                },
              ),
              _MenuTile(
                icon: Icons.star_rounded,
                label: L10n.t('setActive'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  state.selectServer(server);
                  showNovaToast(context, L10n.t('activeServerSet'), kind: ToastKind.success);
                },
              ),
              const SizedBox(height: 8),
              NovaButton(
                label: L10n.t('close'),
                variant: NovaButtonVariant.ghost,
                onPressed: () => Navigator.of(sheetContext).pop(),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return InkWell(
      onTap: onTap,
      borderRadius: NovaRadii.rMd,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 19, color: p.primaryBright),
            const SizedBox(width: 14),
            Expanded(child: Text(label, style: NovaTextStyles.body(p.text))),
            Icon(Icons.chevron_right_rounded, size: 18, color: p.textDim),
          ],
        ),
      ),
    );
  }
}
