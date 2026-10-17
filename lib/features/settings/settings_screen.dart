import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../core/strings.dart';
import '../../design/theme.dart';
import '../../design/tokens.dart';
import '../../design/widgets/brand.dart';
import '../../design/widgets/buttons.dart';
import '../../design/widgets/display.dart';
import '../../design/widgets/feedback.dart';
import '../../design/widgets/inputs.dart';
import '../../design/widgets/surfaces.dart';
import '../../state/app_state.dart';
import '../account/account_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final AppState state = AppScope.of(context);
    final p = context.nova;
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(NovaSpace.page, 10, NovaSpace.page, 130),
        physics: const BouncingScrollPhysics(),
        children: <Widget>[
          Row(
            children: <Widget>[
              const BrandLockup(markSize: 30, fontSize: 14, letterSpacing: 2.2),
              const Spacer(),
              Pill(label: 'v${AppConfig.versionName}', tone: PillTone.neutral, dense: true),
            ],
          ),
          const SizedBox(height: 16),
          Text(L10n.t('settingsTitle'), style: NovaTextStyles.display(27, p.text)),
          const SizedBox(height: 3),
          Text(L10n.t('settingsSubtitle'), style: NovaTextStyles.small(p.textMuted)),
          const SizedBox(height: 16),
          PressableScale(
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AccountScreen())),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: NovaGradients.card(p),
                borderRadius: NovaRadii.rLg,
                border: Border.all(color: p.stroke),
                boxShadow: NovaShadows.soft(p),
              ),
              child: Row(
                children: <Widget>[
                  AvatarBadge(name: state.user?.login ?? 'N', imageUrl: state.user?.avatarUrl, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          state.user?.login ?? L10n.t('notConfigured'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: NovaTextStyles.bodyStrong(p.text),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          L10n.t('accountSecurity'),
                          style: NovaTextStyles.caption(p.textDim),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: p.textDim),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          SectionHeader(title: L10n.t('appearance'), icon: Icons.palette_rounded),
          SectionCard(
            title: L10n.t('theme'),
            icon: Icons.contrast_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                NovaSegmented(
                  labels: <String>[L10n.t('themeDark'), L10n.t('themeLight'), L10n.t('themeSystem')],
                  index: _themeIndex(state.themeMode),
                  onChanged: (int i) {
                    final String value = i == 0 ? 'dark' : (i == 1 ? 'light' : 'system');
                    state.setThemeMode(value);
                  },
                  icons: const <IconData>[Icons.dark_mode_rounded, Icons.light_mode_rounded, Icons.brightness_auto_rounded],
                ),
                const SizedBox(height: 8),
                Text(
                  state.themeMode == 'system' ? L10n.t('themeSystem') : (state.themeMode == 'light' ? L10n.t('themeLightHint') : L10n.t('themeDarkHint')),
                  style: NovaTextStyles.caption(p.textDim),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SectionCard(
            title: L10n.t('language'),
            icon: Icons.translate_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                NovaSegmented(
                  labels: <String>[L10n.t('languageArabic'), L10n.t('languageEnglish')],
                  index: state.language == 'ar' ? 0 : 1,
                  onChanged: (int i) {
                    if (i == 0) {
                      state.setLanguage('ar');
                    } else {
                      state.setLanguage('en');
                    }
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Icon(Icons.format_textdirection_r_to_l_rounded, size: 13, color: p.textDim),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(L10n.t('rtlNote'), style: NovaTextStyles.caption(p.textDim)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SectionHeader(title: L10n.t('notifications'), icon: Icons.notifications_active_rounded),
          Container(
            decoration: BoxDecoration(
              color: p.cardSoft,
              borderRadius: NovaRadii.rLg,
              border: Border.all(color: p.stroke),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: <Widget>[
                NovaSwitchTile(
                  title: L10n.t('notificationsBackups'),
                  subtitle: L10n.t('notificationsHint'),
                  value: state.notifyBackups,
                  onChanged: state.setNotifyBackups,
                  icon: Icons.backup_rounded,
                ),
                SoftDivider(),
                NovaSwitchTile(
                  title: L10n.t('notificationsFailures'),
                  subtitle: L10n.t('githubRunnersNote'),
                  value: state.notifyFailures,
                  onChanged: state.setNotifyFailures,
                  icon: Icons.warning_amber_rounded,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SectionHeader(title: L10n.t('dataTitle'), icon: Icons.storage_rounded),
          SectionCard(
            title: L10n.t('clearCache'),
            icon: Icons.cleaning_services_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(L10n.t('clearCacheBody'), style: NovaTextStyles.small(p.textMuted)),
                const SizedBox(height: 10),
                NovaButton(
                  label: L10n.t('clearLocalData'),
                  icon: Icons.delete_sweep_rounded,
                  size: NovaButtonSize.compact,
                  variant: NovaButtonVariant.ghost,
                  onPressed: () async {
                    final bool ok = await showNovaConfirm(
                      context,
                      title: L10n.t('clearLocalData'),
                      body: L10n.t('clearLocalDataBody'),
                      confirmLabel: L10n.t('delete'),
                      danger: true,
                      icon: Icons.delete_forever_rounded,
                    );
                    if (!ok) return;
                    await state.clearCache();
                    if (!context.mounted) return;
                    showNovaToast(context, L10n.t('cacheCleared'), kind: ToastKind.success);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SectionHeader(title: L10n.t('aboutTitle'), icon: Icons.info_rounded),
          SectionCard(
            title: L10n.t('aboutTitle'),
            icon: Icons.auto_awesome_rounded,
            child: Column(
              children: <Widget>[
                _AboutRow(label: L10n.t('versionLabel2'), value: AppConfig.versionName),
                _AboutRow(label: L10n.t('packageLabel'), value: AppConfig.packageName, mono: true),
                _AboutRow(
                  label: L10n.t('githubAppLabel'),
                  value: AppConfig.githubAppSlug,
                  onTap: () => launchUrl(Uri.parse(AppConfig.appPageUrl), mode: LaunchMode.externalApplication),
                ),
                _AboutRow(
                  label: L10n.t('repositoriesTitle'),
                  value: 'github.com',
                  onTap: () => launchUrl(Uri.parse('https://github.com/abiedadam0077/NOVA-CRAFT'), mode: LaunchMode.externalApplication),
                ),
                _AboutRow(
                  label: L10n.t('licenses'),
                  value: L10n.t('viewDetails'),
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: 'NOVA CRAFT',
                    applicationVersion: AppConfig.versionName,
                  ),
                ),
                _AboutRow(
                  label: L10n.t('openSourceNote'),
                  value: '',
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: Column(
              children: <Widget>[
                const LogoMark(size: 46, glow: false),
                const SizedBox(height: 8),
                Text(L10n.t('madeWith'), style: NovaTextStyles.caption(p.textDim)),
                const SizedBox(height: 2),
                Text(L10n.t('notAffiliated'), style: NovaTextStyles.caption(p.textDim)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int _themeIndex(String mode) {
    switch (mode) {
      case 'light':
        return 1;
      case 'system':
        return 2;
      default:
        return 0;
    }
  }
}

class _AboutRow extends StatelessWidget {
  const _AboutRow({required this.label, required this.value, this.mono = false, this.onTap});

  final String label;
  final String value;
  final bool mono;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        child: Row(
          children: <Widget>[
            Expanded(child: Text(label, style: NovaTextStyles.small(p.textMuted))),
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: mono ? NovaTextStyles.mono(10, p.textDim) : NovaTextStyles.caption(p.textDim),
              ),
            ),
            if (onTap != null) ...<Widget>[
              const SizedBox(width: 3),
              Icon(Icons.chevron_right_rounded, size: 15, color: p.textDim),
            ],
          ],
        ),
      ),
    );
  }
}
