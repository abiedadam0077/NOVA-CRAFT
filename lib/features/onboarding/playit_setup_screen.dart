import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../core/formatters.dart';
import '../../core/models.dart';
import '../../core/playit_api.dart';
import '../../core/strings.dart';
import '../../core/validation.dart';
import '../../design/theme.dart';
import '../../design/tokens.dart';
import '../../design/widgets/background.dart';
import '../../design/widgets/brand.dart';
import '../../design/widgets/buttons.dart';
import '../../design/widgets/display.dart';
import '../../design/widgets/feedback.dart';
import '../../design/widgets/inputs.dart';
import '../../design/widgets/nav.dart';
import '../../design/widgets/surfaces.dart';
import '../../state/app_state.dart';

/// Step three of first run: store the user's Playit key as a GitHub Actions
/// Secret. Agent connectivity is a separate runner status; saving a key does
/// not require the Agent to already be online. Tunnel creation stays manual.
class PlayitSetupScreen extends StatefulWidget {
  const PlayitSetupScreen({super.key, required this.repo, required this.onDone});

  final GhRepo repo;
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
  bool _skipping = false;
  bool _loadingStored = true;
  String? _storedSecret;
  String? _error;
  String? _note;
  PlayitAgentState? _agent;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final String? secret = await AppScope.read(context).store.playitSecret();
      if (!mounted) return;
      setState(() {
        _storedSecret = secret;
        _loadingStored = false;
      });
    });
  }

  @override
  void dispose() {
    _secret.dispose();
    _playit.dispose();
    super.dispose();
  }

  Future<void> _openAgentSetup() async {
    await launchUrl(Uri.parse(AppConfig.playitAgentUrl), mode: LaunchMode.externalApplication);
  }

  Future<void> _openTunnels() async {
    await launchUrl(Uri.parse(AppConfig.playitDashboard), mode: LaunchMode.externalApplication);
  }

  String? _validate(String value) {
    return Validation.validPlayitSecret(value) ? null : L10n.t('playitSecretInvalid');
  }

  /// Asks Playit whether this key is real. The key is never logged.
  String get _candidateSecret => _secret.text.trim().isNotEmpty ? _secret.text.trim() : (_storedSecret ?? '');

  Future<void> _verify() async {
    final String? problem = _validate(_candidateSecret);
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
      final PlayitAgentState state = await _playit.agentState(_candidateSecret);
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
    return L10n.t('playitNetworkError');
  }

  Future<void> _save() async {
    if (_validate(_candidateSecret) != null) {
      setState(() => _error = L10n.t('playitSecretInvalid'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final AppState state = AppScope.read(context);
      final String? provided = _secret.text.trim().isEmpty ? null : _secret.text.trim();
      final bool saved = await state.installPlayitSecretForRepo(
        widget.repo.owner,
        widget.repo.name,
        provided: provided,
      );
      if (!saved) throw StateError('missing-playit-secret');
      state.markPendingRepoPlayitReady();
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      _secret.clear();
      widget.onDone();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = Fmt.error(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _skip() async {
    final bool ok = await showNovaConfirm(
      context,
      title: L10n.t('playitSkipForNow'),
      body: L10n.t('playitSkipBody'),
      confirmLabel: L10n.t('playitSkipForNow'),
      icon: Icons.skip_next_rounded,
    );
    if (!ok || !mounted) return;
    setState(() => _skipping = true);
    try {
      final AppState state = AppScope.read(context);
      await state.skipPlayitForNow();
      state.markPendingRepoPlayitReady();
      if (!mounted) return;
      widget.onDone();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = Fmt.error(error));
    } finally {
      if (mounted) setState(() => _skipping = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    final PlayitAgentState? agent = _agent;
    final List<PlayitTunnel> javaTunnels = agent?.tunnelsFor(bedrock: false) ?? <PlayitTunnel>[];
    final List<PlayitTunnel> bedrockTunnels = agent?.tunnelsFor(bedrock: true) ?? <PlayitTunnel>[];
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
                          const SizedBox(height: 12),
                          _Step(number: 4, text: L10n.t('playitSetupStep4')),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    InfoBanner(
                      title: L10n.t('repository'),
                      body: widget.repo.fullName,
                      icon: Icons.lock_outline_rounded,
                      color: p.primaryBright,
                      dense: true,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: NovaButton(
                            label: L10n.t('openPlayitAgent'),
                            icon: Icons.open_in_new_rounded,
                            variant: NovaButtonVariant.secondary,
                            size: NovaButtonSize.compact,
                            onPressed: _openAgentSetup,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: NovaButton(
                            label: L10n.t('openPlayitTunnels'),
                            icon: Icons.hub_rounded,
                            variant: NovaButtonVariant.secondary,
                            size: NovaButtonSize.compact,
                            onPressed: _openTunnels,
                          ),
                        ),
                      ],
                    ),
                    if (_loadingStored) ...<Widget>[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(minHeight: 2),
                    ],
                    const SizedBox(height: 20),
                    NovaField(
                      label: L10n.t('playitKeyLabel'),
                      hint: '••••••••••••••••',
                      controller: _secret,
                      obscure: _obscure,
                      prefixIcon: Icons.key_rounded,
                      helper: _storedSecret != null && _secret.text.isEmpty
                          ? L10n.t('playitStoredUse')
                          : L10n.t('playitKeyBody'),
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
                        label: L10n.t('playitSaveSecret'),
                        icon: Icons.lock_rounded,
                        loading: _saving,
                        onPressed: _saving || _loadingStored ? null : _save,
                      ),
                      const SizedBox(height: 8),
                      NovaButton(
                        label: L10n.t('playitCheckAgent'),
                        icon: Icons.shield_outlined,
                        variant: NovaButtonVariant.secondary,
                        loading: _checking,
                        onPressed: _checking || _loadingStored ? null : _verify,
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
                        agent: agent,
                        javaTunnels: javaTunnels,
                        bedrockTunnels: bedrockTunnels,
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
                    ] else ...<Widget>[
                      const SizedBox(height: 8),
                      NovaButton(
                        label: L10n.t('playitSkipForNow'),
                        icon: Icons.skip_next_rounded,
                        size: NovaButtonSize.compact,
                        variant: NovaButtonVariant.ghost,
                        loading: _skipping,
                        onPressed: _skipping || _loadingStored || _checking ? null : _skip,
                      ),
                    ],
                    const SizedBox(height: 14),
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
    required this.javaTunnels,
    required this.bedrockTunnels,
    this.note,
  });

  final PlayitAgentState agent;
  final List<PlayitTunnel> javaTunnels;
  final List<PlayitTunnel> bedrockTunnels;
  final String? note;

  String _tunnelLabel(String base, PlayitTunnel tunnel) {
    final String identity = tunnel.name.isNotEmpty ? tunnel.name : tunnel.id;
    return identity.isEmpty ? base : '$base · $identity';
  }

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
          if (javaTunnels.isEmpty)
            _MissingRow(label: L10n.t('playitJavaTunnel'))
          else
            for (final PlayitTunnel tunnel in javaTunnels)
              _TunnelRow(
                label: javaTunnels.length == 1 ? L10n.t('playitJavaTunnel') : _tunnelLabel(L10n.t('playitJavaTunnel'), tunnel),
                tunnel: tunnel,
                color: p.primaryBright,
              ),
          const SizedBox(height: 8),
          if (bedrockTunnels.isEmpty)
            _MissingRow(label: L10n.t('playitBedrockTunnel'))
          else
            for (final PlayitTunnel tunnel in bedrockTunnels)
              _TunnelRow(
                label: bedrockTunnels.length == 1 ? L10n.t('playitBedrockTunnel') : _tunnelLabel(L10n.t('playitBedrockTunnel'), tunnel),
                tunnel: tunnel,
                color: p.violet,
              ),
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
