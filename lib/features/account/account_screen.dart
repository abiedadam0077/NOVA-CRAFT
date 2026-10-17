import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../core/formatters.dart';
import '../../core/models.dart';
import '../../core/strings.dart';
import '../../design/theme.dart';
import '../../design/tokens.dart';
import '../../design/widgets/background.dart';
import '../../design/widgets/buttons.dart';
import '../../design/widgets/display.dart';
import '../../design/widgets/feedback.dart';
import '../../design/widgets/nav.dart';
import '../../design/widgets/surfaces.dart';
import '../../state/app_state.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  List<GhInstallation> _installations = <GhInstallation>[];
  int _repoCount = 0;
  bool _loadingRepos = true;
  String? _reposError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loadingRepos = true;
      _reposError = null;
    });
    try {
      final AppState state = AppScope.read(context);
      final List<GhInstallation> installations = await state.api.listInstallations();
      int repos = 0;
      for (final GhInstallation installation in installations) {
        final List<GhRepo> found = await state.api.listInstallationRepos(installation.id);
        repos += found.length;
      }
      if (!mounted) return;
      setState(() {
        _installations = installations;
        _repoCount = repos;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _reposError = Fmt.error(error));
    } finally {
      if (mounted) setState(() => _loadingRepos = false);
    }
  }

  Future<void> _signOut() async {
    final bool ok = await showNovaConfirm(
      context,
      title: L10n.t('signOut'),
      body: L10n.t('disconnectBody'),
      confirmLabel: L10n.t('signOut'),
      danger: true,
      icon: Icons.logout_rounded,
    );
    if (!ok || !mounted) return;
    final AppState state = AppScope.read(context);
    Navigator.of(context).popUntil((Route<dynamic> route) => route.isFirst);
    await state.signOut();
  }

  Future<void> _clearLocalData() async {
    final bool ok = await showNovaConfirm(
      context,
      title: L10n.t('clearLocalData'),
      body: L10n.t('clearLocalDataBody'),
      confirmLabel: L10n.t('delete'),
      danger: true,
      icon: Icons.delete_forever_rounded,
    );
    if (!ok || !mounted) return;
    final AppState state = AppScope.read(context);
    Navigator.of(context).popUntil((Route<dynamic> route) => route.isFirst);
    await state.signOut(clearLocalData: true);
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = AppScope.of(context);
    final p = context.nova;
    final GhUser? user = state.user;
    final ServerConfig? server = state.selected;
    final bool playitLinked = server != null && server.connectionHostPort.isNotEmpty;

    return Scaffold(
      backgroundColor: p.bg,
      body: AuroraBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: <Widget>[
              const NovaTopBar(title: null, showBrand: true),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(NovaSpace.page, 0, NovaSpace.page, 30),
                  physics: const BouncingScrollPhysics(),
                  children: <Widget>[
                    Text(L10n.t('accountTitle'), style: NovaTextStyles.display(26, p.text)),
                    const SizedBox(height: 4),
                    Text(L10n.t('accountSubtitle'), style: NovaTextStyles.small(p.textMuted)),
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        gradient: NovaGradients.cardGlow(p, p.primary),
                        borderRadius: NovaRadii.rXl,
                        border: Border.all(color: p.primary.withValues(alpha: 0.28)),
                        boxShadow: NovaShadows.soft(p),
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              AvatarBadge(
                                name: user?.login ?? 'N',
                                imageUrl: user?.avatarUrl,
                                size: 58,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      user == null ? L10n.t('unknown') : user.login,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: NovaTextStyles.display(20, p.text),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      user == null ? L10n.t('disconnected') : L10n.t('githubConnected'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: NovaTextStyles.small(p.textMuted),
                                    ),
                                  ],
                                ),
                              ),
                              Pill(
                                label: user == null ? L10n.t('disconnected') : L10n.t('connected'),
                                tone: user == null ? PillTone.danger : PillTone.success,
                                dense: true,
                                icon: user == null ? Icons.link_off_rounded : Icons.verified_rounded,
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: _CountBox(
                                  label: L10n.t('installationsTitle'),
                                  value: _loadingRepos ? '—' : '${_installations.length}',
                                  icon: Icons.apps_rounded,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _CountBox(
                                  label: L10n.t('repositoriesTitle'),
                                  value: _loadingRepos ? '—' : '$_repoCount',
                                  icon: Icons.folder_copy_rounded,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _CountBox(
                                  label: L10n.t('serversCount'),
                                  value: '${state.servers.length}',
                                  icon: Icons.dns_rounded,
                                ),
                              ),
                            ],
                          ),
                          if (_reposError != null) ...<Widget>[
                            const SizedBox(height: 10),
                            InlineError(message: _reposError!, onRetry: _load),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    SectionHeader(
                      title: L10n.t('githubAccount'),
                      icon: Icons.code_rounded,
                      actionLabel: L10n.t('repositoriesTitle'),
                      onAction: () => launchUrl(
                        Uri.parse('https://github.com/${user?.login ?? ''}'),
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: p.cardSoft,
                        borderRadius: NovaRadii.rLg,
                        border: Border.all(color: p.stroke),
                      ),
                      child: Column(
                        children: <Widget>[
                          InfoRow(label: L10n.t('permissionsTitle'), value: '', icon: Icons.admin_panel_settings_rounded),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 14),
                            child: Column(
                              children: <Widget>[
                                _PermissionRow(label: 'contents', text: 'read/write'),
                                _PermissionRow(label: 'actions', text: 'read/write'),
                                _PermissionRow(label: 'secrets', text: 'read/write'),
                                _PermissionRow(label: 'workflows', text: 'write'),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          InfoRow(
                            label: L10n.t('githubAppLabel'),
                            value: AppConfig.githubAppSlug,
                            monospace: true,
                            icon: Icons.extension_rounded,
                            onTap: () => launchUrl(Uri.parse(AppConfig.appPageUrl), mode: LaunchMode.externalApplication),
                          ),
                          const SizedBox(height: 6),
                          InfoRow(
                            label: L10n.t('managePlayit'),
                            value: 'github.com',
                            icon: Icons.open_in_new_rounded,
                            onTap: () => launchUrl(Uri.parse(AppConfig.manageInstallationsUrl), mode: LaunchMode.externalApplication),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    SectionHeader(title: L10n.t('playitAccount'), icon: Icons.hub_rounded),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: p.cardSoft,
                        borderRadius: NovaRadii.rLg,
                        border: Border.all(color: p.stroke),
                      ),
                      child: Column(
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: p.violet.withValues(alpha: 0.14),
                                  borderRadius: NovaRadii.rXs,
                                  border: Border.all(color: p.violet.withValues(alpha: 0.28)),
                                ),
                                child: Icon(Icons.hub_rounded, size: 19, color: p.violet),
                              ),
                              const SizedBox(width: 11),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text('Playit.gg', style: NovaTextStyles.bodyStrong(p.text)),
                                    Text(
                                      playitLinked ? (server?.connectionHostPort ?? '') : L10n.t('playitNotLinked'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: NovaTextStyles.caption(p.textDim),
                                    ),
                                  ],
                                ),
                              ),
                              NovaButton(
                                label: L10n.t('managePlayit'),
                                size: NovaButtonSize.compact,
                                expand: false,
                                variant: NovaButtonVariant.secondary,
                                onPressed: () => launchUrl(Uri.parse(AppConfig.playitDashboard), mode: LaunchMode.externalApplication),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(L10n.t('playitNoApi'), style: NovaTextStyles.caption(p.textDim)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    SectionHeader(title: L10n.t('securityTitle'), icon: Icons.security_rounded),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: p.cardSoft,
                        borderRadius: NovaRadii.rLg,
                        border: Border.all(color: p.stroke),
                      ),
                      child: Column(
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Icon(Icons.enhanced_encryption_rounded, size: 18, color: p.successBright),
                              const SizedBox(width: 9),
                              Expanded(child: Text(L10n.t('securityThreadSafe'), style: NovaTextStyles.smallStrong(p.text))),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(L10n.t('securityBody'), style: NovaTextStyles.small(p.textDim)),
                          const SizedBox(height: 10),
                          const SoftDivider(),
                          const SizedBox(height: 8),
                          _SecurityLine(icon: Icons.phonelink_lock_rounded, label: L10n.t('securityTokens')),
                          _SecurityLine(icon: Icons.key_rounded, label: L10n.t('securitySecrets')),
                          _SecurityLine(icon: Icons.visibility_off_rounded, label: L10n.t('securityNoPlain')),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    NovaButton(
                      label: L10n.t('signOut'),
                      icon: Icons.logout_rounded,
                      variant: NovaButtonVariant.secondary,
                      onPressed: _signOut,
                    ),
                    const SizedBox(height: 8),
                    NovaButton(
                      label: L10n.t('clearLocalData'),
                      icon: Icons.delete_forever_rounded,
                      variant: NovaButtonVariant.ghost,
                      onPressed: _clearLocalData,
                    ),
                    const SizedBox(height: 14),
                    Center(
                      child: Text(
                        'NOVA CRAFT ${AppConfig.versionName}',
                        style: NovaTextStyles.caption(p.textDim),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountBox extends StatelessWidget {
  const _CountBox({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: NovaRadii.md,
        border: Border.all(color: p.stroke),
      ),
      child: Column(
        children: <Widget>[
          Icon(icon, size: 15, color: p.primaryBright),
          const SizedBox(height: 4),
          Text(value, style: NovaTextStyles.number(17, p.text)),
          const SizedBox(height: 1),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: NovaTextStyles.caption(p.textDim),
          ),
        ],
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          Icon(Icons.check_rounded, size: 12, color: p.successBright),
          const SizedBox(width: 6),
          Expanded(child: Text(label, style: NovaTextStyles.mono(11, p.textMuted))),
          Text(text, style: NovaTextStyles.caption(p.textDim)),
        ],
      ),
    );
  }
}

class _SecurityLine extends StatelessWidget {
  const _SecurityLine({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 14, color: p.primaryBright),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: NovaTextStyles.caption(p.textMuted))),
        ],
      ),
    );
  }
}
