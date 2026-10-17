import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../core/formatters.dart';
import '../../core/models.dart';
import '../../core/playit_api.dart';
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

/// Step two of the first run: connect the Playit.gg agent.
///
/// The secret is verified against Playit's real agent API before it is
/// accepted, so "connected" is never shown for an unverified key. A public
/// address is displayed only when Playit itself reports one for a tunnel of
/// the right edition. Nothing here claims 24/7 uptime or a fixed address.
class PlayitSetupScreen extends StatefulWidget {
  const PlayitSetupScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<PlayitSetupScreen> createState() => _PlayitSetupScreenState();
}

class _PlayitSetupScreenState extends State<PlayitSetupScreen> {
  final TextEditingController _secret = TextEditingController();
  final PlayitApi _playit = PlayitApi();
  bool _obscure = true;
  bool _saving = false;
  bool _checking = false;
  String? _error;
  String? _note;
  PlayitAgentState? _agent;

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

  /// Asks Playit whether this key is real. The key is never logged.
  Future<void> _verify() async {
    final String? problem = _validate(_secret.text);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _checking = true;
      _error = null;
      _note = null;
    });
    try {
      final PlayitAgentState state = await _playit.agentState(_secret.text);
      if (!mounted) return;
      if (!state.ok) {
        setState(() {
          _agent = null;
          _error = _explain(state.error);
        });
        return;
      }
      setState(() {
        _agent = state;
        _note = state.tunnels.isEmpty ? L10n.t('playitNoTunnelsYet') : null;
      });
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  String _explain(String raw) {
    final String value = raw.toLowerCase();
    if (value.contains('invalidagentkey') || value.contains('unauthorized') || value.contains('401')) {
      return L10n.t('playitKeyRejected');
    }
    if (value.contains('requiresverifiedaccount')) return L10n.t('playitNeedsVerifiedAccount');
    if (value.contains('requiresplayitpremium')) return L10n.t('playitNeedsPremium');
    if (value.contains('timeout') || value.contains('socket') || value.contains('failed host lookup')) {
      return L10n.t('playitNetworkError');
    }
    return raw.isEmpty ? L10n.t('errorGeneric') : raw;
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await AppScope.read(context).savePlayitSecret(_secret.text.trim());
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      _secret.clear();
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
    await AppScope.read(context).skipPlayitForNow();
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    final PlayitAgentState? agent = _agent;
    final PlayitTunnel? javaTunnel = agent?.tunnelFor(bedrock: false);
    final PlayitTunnel? bedrockTunnel = agent?.tunnelFor(bedrock: true);
    final bool verified = agent != null && agent.ok;
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
                      height: 140,
                      alignment: Alignment.center,
                      radius: NovaRadii.rXl,
                    ),
                    const SizedBox(height: 18),
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
                        if (_error != null || _agent != null) {
                          setState(() {
                            _error = null;
                            _agent = null;
                            _note = null;
                          });
                        }
                      },
                      suffix: NovaIconButton(
                        icon: _obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                        onTap: () => setState(() => _obscure = !_obscure),
                        size: 34,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (!verified) ...<Widget>[
                      NovaButton(
                        label: L10n.t('playitVerifyKey'),
                        icon: Icons.shield_outlined,
                        loading: _checking,
                        onPressed: _checking ? null : _verify,
                      ),
                      const SizedBox(height: 10),
                      InfoBanner(
                        body: L10n.t('playitVerifyNote'),
                        icon: Icons.verified_outlined,
                        color: p.primaryBright,
                        dense: true,
                      ),
                    ] else ...<Widget>[
                      _AgentCard(
                        agent: agent!,
                        javaTunnel: javaTunnel,
                        bedrockTunnel: bedrockTunnel,
                        note: _note,
                      ),
                      const SizedBox(height: 14),
                      NovaButton(
                        label: L10n.t('continue'),
                        icon: Icons.arrow_forward_rounded,
                        loading: _saving,
                        onPressed: _saving ? null : _save,
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _checking ? null : _verify,
                        style: TextButton.styleFrom(foregroundColor: p.textMuted),
                        child: Text(
                          L10n.t('playitRecheck'),
                          style: NovaTextStyles.small(p.textMuted),
                        ),
                      ),
                    ],
                    if (verified) ...<Widget>[
                      const SizedBox(height: 8),
                      InfoBanner(
                        body: L10n.t('playitAddressRuntimeNote'),
                        icon: Icons.info_outline_rounded,
                        color: p.violet,
                        dense: true,
                      ),
                    ],
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

/// Shows what Playit actually reported: the agent id and each tunnel with its
/// real address, or an explicit "no address allocated yet".
class _AgentCard extends StatelessWidget {
  const _AgentCard({
    required this.agent,
    required this.javaTunnel,
    required this.bedrockTunnel,
    this.note,
  });

  final PlayitAgentState agent;
  final PlayitTunnel? javaTunnel;
  final PlayitTunnel? bedrockTunnel;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.success.withValues(alpha: 0.09),
        borderRadius: NovaRadii.rLg,
        border: Border.all(color: p.success.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.check_circle_rounded, size: 20, color: p.successBright),
              const SizedBox(width: 8),
              Expanded(
                child: Text(L10n.t('playitKeyVerified'), style: NovaTextStyles.bodyStrong(p.successBright)),
              ),
            ],
          ),
          if (agent.agentId.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            InfoRow(label: L10n.t('playitAgentId'), value: agent.agentId, monospace: true),
          ],
          const SizedBox(height: 10),
          if (javaTunnel != null)
            _TunnelRow(label: L10n.t('playitJavaTunnel'), tunnel: javaTunnel!, color: p.primaryBright)
          else
            _MissingRow(label: L10n.t('playitJavaTunnel')),
          const SizedBox(height: 8),
          if (bedrockTunnel != null)
            _TunnelRow(label: L10n.t('playitBedrockTunnel'), tunnel: bedrockTunnel!, color: p.violet)
          else
            _MissingRow(label: L10n.t('playitBedrockTunnel')),
          if (note != null) ...<Widget>[
            const SizedBox(height: 10),
            Text(note!, style: NovaTextStyles.small(p.textMuted)),
          ],
        ],
      ),
    );
  }
}

class _TunnelRow extends StatelessWidget {
  const _TunnelRow({required this.label, required this.tunnel, required this.color});

  final String label;
  final PlayitTunnel tunnel;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        InfoRow(label: label, value: tunnel.hasAddress ? tunnel.address : L10n.t('playitAwaitingAddress'), monospace: tunnel.hasAddress),
        if (!tunnel.enabled)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              L10n.f('playitTunnelDisabled', <String, String>{'reason': tunnel.disabledReason}),
              style: NovaTextStyles.caption(p.warning),
            ),
          ),
        if (tunnel.hasAddress && tunnel.enabled)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              children: <Widget>[
                Icon(Icons.public_rounded, size: 12, color: color),
                const SizedBox(width: 5),
                Text(L10n.t('playitAddressLive'), style: NovaTextStyles.caption(color)),
              ],
            ),
          ),
      ],
    );
  }
}

class _MissingRow extends StatelessWidget {
  const _MissingRow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return InfoRow(label: label, value: L10n.t('playitNoTunnel'), trailing: Icon(Icons.remove_circle_outline_rounded, size: 14, color: p.textDim));
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
