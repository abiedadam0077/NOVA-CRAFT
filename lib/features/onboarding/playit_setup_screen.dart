import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../core/strings.dart';
import '../../design/theme.dart';
import '../../design/tokens.dart';
import '../../design/widgets/background.dart';
import '../../design/widgets/brand.dart';
import '../../design/widgets/buttons.dart';
import '../../design/widgets/feedback.dart';
import '../../design/widgets/inputs.dart';
import '../../design/widgets/nav.dart';
import '../../design/widgets/surfaces.dart';
import '../../state/app_state.dart';

/// Step two of the first run: prepare the Playit.gg agent.
///
/// The app cannot create a Playit tunnel by itself (Playit has no public API
/// for that), so it walks the user through the dashboard, stores the agent
/// secret encrypted on the device, and later installs it as a repository
/// secret. Nothing is ever reported as "connected" here — that only happens
/// after a real cycle reports a live tunnel.
class PlayitSetupScreen extends StatefulWidget {
  const PlayitSetupScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<PlayitSetupScreen> createState() => _PlayitSetupScreenState();
}

class _PlayitSetupScreenState extends State<PlayitSetupScreen> {
  final TextEditingController _secret = TextEditingController();
  bool _obscure = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _secret.dispose();
    super.dispose();
  }

  Future<void> _openDashboard() async {
    await launchUrl(Uri.parse(AppConfig.playitAgentUrl), mode: LaunchMode.externalApplication);
  }

  String? _validate(String value) {
    final String v = value.trim();
    if (v.isEmpty) return L10n.t('playitSecretInvalid');
    if (v.contains(RegExp(r'\s'))) return L10n.t('playitSecretInvalid');
    if (v.length < 20) return L10n.t('playitSecretInvalid');
    return null;
  }

  Future<void> _save() async {
    final String? problem = _validate(_secret.text);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await AppScope.read(context).savePlayitSecret(_secret.text.trim());
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      widget.onDone();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = L10n.t('playitSecretInvalid'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _skip() async {
    final bool ok = await showNovaConfirm(
      context,
      title: L10n.t('playitSkipForNow'),
      body: L10n.t('playitVerifyNote'),
      confirmLabel: L10n.t('playitSkipForNow'),
      danger: true,
    );
    if (!ok || !mounted) return;
    AppScope.read(context).skipPlayitForNow();
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return Scaffold(
      backgroundColor: p.bg,
      body: AuroraBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: <Widget>[
              const NovaTopBar(showBrand: true),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(NovaSpace.page, 0, NovaSpace.page, 40),
                  children: <Widget>[
                    ArtBanner(
                      asset: 'assets/images/art_network.jpg',
                      height: 150,
                      alignment: Alignment.center,
                      radius: NovaRadii.rXl,
                    ),
                    const SizedBox(height: 20),
                    Text(L10n.t('playitSetupTitle'), style: NovaTextStyles.display(26, p.text)),
                    const SizedBox(height: 8),
                    Text(L10n.t('playitSetupBody'), style: NovaTextStyles.body(p.textMuted)),
                    const SizedBox(height: 18),
                    NovaCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: <Widget>[
                          _Step(number: 1, text: L10n.t('playitSetupStep1')),
                          const SizedBox(height: 12),
                          _Step(number: 2, text: L10n.t('playitSetupStep2')),
                          const SizedBox(height: 12),
                          _Step(number: 3, text: L10n.t('playitSetupStep3')),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    NovaButton(
                      label: L10n.t('openPlayitDashboard'),
                      icon: Icons.open_in_new_rounded,
                      variant: NovaButtonVariant.secondary,
                      height: 48,
                      size: NovaButtonSize.compact,
                      onPressed: _openDashboard,
                    ),
                    const SizedBox(height: 20),
                    NovaField(
                      label: L10n.t('playitKeyLabel'),
                      hint: '••••••••••••••••',
                      controller: _secret,
                      obscure: _obscure,
                      prefixIcon: Icons.key_rounded,
                      helper: L10n.t('playitKeyBody'),
                      errorText: _error,
                      onChanged: (_) {
                        if (_error != null) setState(() => _error = null);
                      },
                      suffix: NovaIconButton(
                        icon: _obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                        onTap: () => setState(() => _obscure = !_obscure),
                        size: 34,
                      ),
                    ),
                    const SizedBox(height: 16),
                    NovaButton(
                      label: L10n.t('continue'),
                      icon: Icons.arrow_forward_rounded,
                      onPressed: _saving ? null : _save,
                      loading: _saving,
                    ),
                    const SizedBox(height: 10),
                    InfoBanner(
                      body: L10n.t('playitVerifyNote'),
                      icon: Icons.verified_outlined,
                      color: p.primaryBright,
                      dense: true,
                    ),
                    const SizedBox(height: 14),
                    Center(
                      child: TextButton(
                        onPressed: _saving ? null : _skip,
                        style: TextButton.styleFrom(foregroundColor: p.textDim),
                        child: Text(L10n.t('playitSkipForNow'), style: NovaTextStyles.small(p.textDim)),
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

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: p.primary.withValues(alpha: 0.14),
            shape: BoxShape.circle,
            border: Border.all(color: p.primary.withValues(alpha: 0.35)),
          ),
          child: Text('$number', style: NovaTextStyles.monoStrong(11, p.primaryBright)),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: NovaTextStyles.body(p.textMuted))),
      ],
    );
  }
}
