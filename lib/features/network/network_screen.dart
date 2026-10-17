import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../core/formatters.dart';
import '../../core/minecraft_ping.dart';
import '../../core/models.dart';
import '../../core/playit_api.dart';
import '../../core/provisioner.dart';
import '../../core/strings.dart';
import '../../core/validation.dart';
import '../../design/theme.dart';
import '../../design/tokens.dart';
import '../../design/widgets/buttons.dart';
import '../../design/widgets/display.dart';
import '../../design/widgets/feedback.dart';
import '../../design/widgets/inputs.dart';
import '../../design/widgets/surfaces.dart';
import '../../state/app_state.dart';

class NetworkView extends StatefulWidget {
  const NetworkView({
    super.key,
    required this.config,
    this.active = true,
    this.reportedAddress = '',
    this.runtime,
  });

  final ServerConfig config;
  final bool active;

  /// Address the Playit agent reported in `status.json`. Shown when the config
  /// has no manual override — it is never invented by the app.
  final String reportedAddress;

  /// Latest runner snapshot, used for the real tunnel name/protocol/reasons.
  final ServerRuntime? runtime;

  @override
  State<NetworkView> createState() => _NetworkViewState();
}

class _NetworkViewState extends State<NetworkView> {
  final TextEditingController _address = TextEditingController();
  final TextEditingController _secret = TextEditingController();

  bool _testing = false;
  bool _saving = false;
  bool _savingSecret = false;
  bool _secretPresent = false;
  bool _checkedSecret = false;
  String? _secretError;
  PingResult? _result;
  DateTime? _testedAt;
  String? _testError;
  bool _checkingPlayit = false;
  PlayitAgentState? _playitState;
  String? _playitError;

  @override
  void initState() {
    super.initState();
    _address.text = widget.config.connectionHostPort.isEmpty ? widget.reportedAddress : widget.config.connectionHostPort;
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkSecret());
  }

  @override
  void dispose() {
    _address.dispose();
    _secret.dispose();
    super.dispose();
  }

  String get _effectiveAddress {
    final String configured = widget.config.connectionHostPort;
    if (configured.isNotEmpty) return configured;
    return widget.reportedAddress.replaceFirst('tcp://', '').replaceFirst('udp://', '').trim();
  }

  String get _host => _effectiveAddress.isEmpty
      ? ''
      : Validation.parseHostPort(_effectiveAddress, widget.config.localPort).host;

  String get _javaAddress {
    if (_host.isEmpty) return '';
    final HostPort parsed = Validation.parseHostPort(_effectiveAddress, widget.config.playitJavaPort);
    return '${parsed.host}:${parsed.port}';
  }

  String get _bedrockAddress {
    if (_host.isEmpty) return '';
    final HostPort parsed = Validation.parseHostPort(_effectiveAddress, widget.config.playitBedrockPort);
    return '${parsed.host}:${parsed.port}';
  }

  Future<void> _checkSecret() async {
    try {
      final AppState state = AppScope.read(context);
      final List<String> names = await state.api.listSecretNames(widget.config.repoOwner, widget.config.repoName);
      if (!mounted) return;
      setState(() {
        _secretPresent = names.contains('PLAYIT_SECRET_KEY');
        _checkedSecret = true;
        _secretError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _checkedSecret = true;
        _secretError = Fmt.error(error);
      });
    }
  }

  Future<void> _saveAddress() async {
    setState(() => _saving = true);
    try {
      final AppState state = AppScope.read(context);
      final ServerConfig next = widget.config.copyWith(playitAddress: _address.text.trim());
      await Provisioner.updateConfig(state.api, next);
      state.upsertServer(next);
      if (!mounted) return;
      showNovaToast(context, L10n.t('addressSaved'), kind: ToastKind.success);
    } catch (error) {
      if (!mounted) return;
      showNovaToast(context, Fmt.error(error), kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveSecret() async {
    final String value = _secret.text.trim();
    if (value.isEmpty) return;
    setState(() => _savingSecret = true);
    try {
      final AppState state = AppScope.read(context);
      await Provisioner.writePlayitSecret(state.api, widget.config, value);
      _secret.clear();
      if (!mounted) return;
      showNovaToast(context, L10n.t('secretSaved'), kind: ToastKind.success);
      await _checkSecret();
    } catch (error) {
      if (!mounted) return;
      showNovaToast(context, Fmt.error(error), kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _savingSecret = false);
    }
  }

  Future<void> _test() async {
    if (_host.isEmpty) {
      showNovaToast(context, L10n.t('noAddressConfigured'), kind: ToastKind.warning);
      return;
    }
    setState(() {
      _testing = true;
      _testError = null;
    });
    try {
      final bool bedrock = widget.config.isBedrock;
      final HostPort parsed = Validation.parseHostPort(
        widget.config.connectionHostPort,
        bedrock ? widget.config.playitBedrockPort : widget.config.playitJavaPort,
      );
      final PingResult result = bedrock
          ? await MinecraftPing.bedrock(host: parsed.host, port: parsed.port)
          : await MinecraftPing.java(host: parsed.host, port: parsed.port);
      if (!mounted) return;
      setState(() {
        _result = result;
        _testedAt = DateTime.now();
        _testError = result.online ? null : (result.error ?? L10n.t('connectionFailed'));
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _testError = Fmt.error(error));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  /// Calls Playit's agent API with the locally stored key. This is the only
  /// way the app can state anything about the tunnel without the runner.
  Future<void> _checkPlayit() async {
    setState(() {
      _checkingPlayit = true;
      _playitError = null;
    });
    try {
      final AppState state = AppScope.read(context);
      final PlayitAgentState result = await state.inspectPlayit(bedrock: widget.config.isBedrock);
      if (!mounted) return;
      setState(() {
        if (result.ok) {
          _playitState = result;
        } else {
          _playitState = null;
          _playitError = result.error == 'missing-secret' ? L10n.t('playitSecretMissing') : result.error;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _playitError = Fmt.error(error));
    } finally {
      if (mounted) setState(() => _checkingPlayit = false);
    }
  }

  Future<void> _reconnect() async {
    final bool ok = await showNovaConfirm(
      context,
      title: L10n.t('reconnect'),
      body: L10n.t('restartConfirmBody'),
      confirmLabel: L10n.t('reconnect'),
      icon: Icons.sync_rounded,
    );
    if (!ok || !mounted) return;
    try {
      final AppState state = AppScope.read(context);
      await Provisioner.restartServer(state.api, widget.config, activeRun: false);
      if (!mounted) return;
      showNovaToast(context, L10n.t('actionQueued'), kind: ToastKind.success);
    } catch (error) {
      if (!mounted) return;
      showNovaToast(context, Fmt.error(error), kind: ToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    final bool configured = _host.isNotEmpty;
    final bool online = _result?.online ?? false;
    final String stateLabel = !configured
        ? L10n.t('tunnelUnknown')
        : (online ? L10n.t('tunnelActive') : (_result == null ? L10n.t('tunnelUnknown') : L10n.t('tunnelInactive')));
    final Color stateColor = !configured
        ? p.textMuted
        : (online ? p.success : (_result == null ? p.textMuted : p.danger));

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      physics: const BouncingScrollPhysics(),
      children: <Widget>[
        ClipRRect(
          borderRadius: NovaRadii.rXl,
          child: SizedBox(
            height: 148,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                Image.asset('assets/images/art_network.jpg', fit: BoxFit.cover),
                const DecoratedBox(decoration: BoxDecoration(gradient: NovaGradients.heroScrim)),
                PositionedDirectional(
                  start: 16,
                  bottom: 14,
                  end: 16,
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(L10n.t('networkTitle'), style: NovaTextStyles.display(21, Colors.white)),
                            const SizedBox(height: 2),
                            Text(
                              L10n.t('networkSubtitle'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: NovaTextStyles.small(const Color(0xFFB9C7E8)),
                            ),
                          ],
                        ),
                      ),
                      Pill(
                        label: stateLabel,
                        tone: !configured
                            ? PillTone.neutral
                            : (online ? PillTone.success : (_result == null ? PillTone.neutral : PillTone.danger)),
                        dense: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: L10n.t('serverAddresses'),
          icon: Icons.lan_rounded,
          actionLabel: _testing ? L10n.t('testing') : L10n.t('testConnection'),
          onAction: _testing ? null : _test,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              AddressPill(
                address: _javaAddress.isEmpty ? L10n.t('noAddressYet') : _javaAddress,
                label: L10n.t('javaAddress'),
                compact: true,
                onCopy: _javaAddress.isEmpty
                    ? null
                    : () {
                        Clipboard.setData(ClipboardData(text: _javaAddress));
                        showNovaToast(context, L10n.t('copied'), kind: ToastKind.success);
                      },
              ),
              const SizedBox(height: 8),
              AddressPill(
                address: _bedrockAddress.isEmpty ? L10n.t('noAddressYet') : _bedrockAddress,
                label: L10n.t('bedrockAddress'),
                compact: true,
                onCopy: _bedrockAddress.isEmpty
                    ? null
                    : () {
                        Clipboard.setData(ClipboardData(text: _bedrockAddress));
                        showNovaToast(context, L10n.t('copied'), kind: ToastKind.success);
                      },
              ),
              if (_testing) ...<Widget>[
                const SizedBox(height: 12),
                const LinearProgressIndicator(minHeight: 2),
              ],
              if (_result != null && _result!.online) ...<Widget>[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: p.success.withValues(alpha: 0.10),
                    borderRadius: NovaRadii.rMd,
                    border: Border.all(color: p.success.withValues(alpha: 0.28)),
                  ),
                  child: Column(
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Icon(Icons.check_circle_rounded, size: 16, color: p.successBright),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(L10n.t('connectionVerified'), style: NovaTextStyles.smallStrong(p.successBright)),
                          ),
                          if (_testedAt != null)
                            Text(Fmt.relative(_testedAt), style: NovaTextStyles.caption(p.textDim)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: <Widget>[
                          _metric(p, L10n.t('ping'), '${_result!.latencyMs} ms'),
                          _metric(
                            p,
                            L10n.t('players'),
                            _result!.playersOnline == null
                                ? '—'
                                : '${_result!.playersOnline}/${_result!.playersMax?.toString() ?? '?'}',
                          ),
                          _metric(p, L10n.t('versionLabel'), _result!.version.isEmpty ? '—' : _result!.version),
                        ],
                      ),
                    ],
                  ),
                ),
              ] else if (_testError != null) ...<Widget>[
                const SizedBox(height: 10),
                InfoBanner(
                  body: _testError!,
                  icon: Icons.error_outline_rounded,
                  color: p.danger,
                  actionLabel: L10n.t('retry'),
                  onAction: _test,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        SectionCard(
          title: L10n.t('editAddress'),
          icon: Icons.edit_location_alt_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              NovaField(
                controller: _address,
                hint: 'your-tunnel.playit.gg',
                prefixIcon: Icons.hub_rounded,
                helper: L10n.t('addressFromConfig'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              NovaButton(
                label: L10n.t('saveChanges'),
                loading: _saving,
                size: NovaButtonSize.compact,
                onPressed: _saving ? null : _saveAddress,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SectionCard(
          title: L10n.t('playitAccount'),
          icon: Icons.vpn_key_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              InfoRow(
                label: L10n.t('playitKeyLabel'),
                value: !_checkedSecret
                    ? L10n.t('loading')
                    : (_secretPresent ? L10n.t('playitSecretPresent') : L10n.t('playitSecretMissing')),
                valueColor: _secretPresent ? p.successBright : p.warning,
                icon: _secretPresent ? Icons.lock_rounded : Icons.lock_open_rounded,
              ),
              if (_secretError != null) ...<Widget>[
                const SizedBox(height: 6),
                InlineError(message: _secretError!, onRetry: _checkSecret),
              ],
              const SizedBox(height: 10),
              NovaField(
                controller: _secret,
                label: L10n.t('playitKeyLabel'),
                hint: '••••••••••••',
                prefixIcon: Icons.password_rounded,
                obscure: true,
                helper: L10n.t('playitKeyBody'),
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    child: NovaButton(
                      label: L10n.t('saveAsSecret'),
                      size: NovaButtonSize.compact,
                      variant: NovaButtonVariant.secondary,
                      loading: _savingSecret,
                      onPressed: _savingSecret ? null : _saveSecret,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: NovaButton(
                      label: L10n.t('openPlayitDashboard'),
                      size: NovaButtonSize.compact,
                      variant: NovaButtonVariant.ghost,
                      onPressed: () => launchUrl(Uri.parse(AppConfig.playitDashboard), mode: LaunchMode.externalApplication),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SectionCard(
          title: L10n.t('tunnelStatus'),
          icon: Icons.cable_rounded,
          actionLabel: _checkingPlayit ? L10n.t('loading') : L10n.t('playitCheckNow'),
          onAction: _checkingPlayit ? null : _checkPlayit,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: stateColor, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(stateLabel, style: NovaTextStyles.bodyStrong(stateColor))),
                  NovaButton(
                    label: L10n.t('reconnect'),
                    icon: Icons.sync_rounded,
                    size: NovaButtonSize.compact,
                    expand: false,
                    variant: NovaButtonVariant.secondary,
                    onPressed: _reconnect,
                  ),
                ],
              ),
              if (widget.runtime != null) ...<Widget>[
                const SizedBox(height: 10),
                InfoRow(
                  label: L10n.t('runnerTunnelState'),
                  value: widget.runtime!.tunnelStatus.isEmpty ? L10n.t('unknown') : widget.runtime!.tunnelStatus,
                  valueColor: widget.runtime!.tunnelConnected ? p.successBright : p.textMuted,
                  monospace: true,
                ),
                if (widget.runtime!.tunnelName.isNotEmpty)
                  InfoRow(label: L10n.t('playitTunnelName'), value: widget.runtime!.tunnelName),
                if (widget.runtime!.tunnelProtocol.isNotEmpty)
                  InfoRow(label: L10n.t('playitTunnelProtocol'), value: widget.runtime!.tunnelProtocol, monospace: true),
                if (widget.runtime!.agentId.isNotEmpty)
                  InfoRow(label: L10n.t('playitAgentId'), value: widget.runtime!.agentId, monospace: true),
                for (final String reason in widget.runtime!.tunnelOfflineReasons)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      L10n.f('playitTunnelDisabled', <String, String>{'reason': reason}),
                      style: NovaTextStyles.caption(p.warning),
                    ),
                  ),
              ],
              if (_playitError != null) ...<Widget>[
                const SizedBox(height: 8),
                InlineError(message: _playitError!, onRetry: _checkPlayit),
              ],
              if (_playitState != null) ...<Widget>[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: p.primary.withValues(alpha: 0.07),
                    borderRadius: NovaRadii.rMd,
                    border: Border.all(color: p.primary.withValues(alpha: 0.25)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(L10n.t('playitLiveCheck'), style: NovaTextStyles.caption(p.primaryBright)),
                      if (_playitState!.agentId.isNotEmpty)
                        InfoRow(label: L10n.t('playitAgentId'), value: _playitState!.agentId, monospace: true),
                      ..._playitState!.tunnels.map((PlayitTunnel t) => InfoRow(
                            label: '${t.type} · ${t.protocol}',
                            value: t.hasAddress ? t.address : L10n.t('playitAwaitingAddress'),
                            monospace: t.hasAddress,
                            valueColor: t.hasAddress && t.enabled ? p.successBright : p.textMuted,
                          )),
                      if (_playitState!.tunnels.isEmpty)
                        Text(L10n.t('playitNoTunnelsYet'), style: NovaTextStyles.small(p.textMuted)),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Text(L10n.t('playitFreePlan'), style: NovaTextStyles.small(p.textMuted)),
              const SizedBox(height: 6),
              Text(L10n.t('playitStatusSource'), style: NovaTextStyles.caption(p.textDim)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        InfoBanner(
          body: L10n.t('githubRunnersNote'),
          icon: Icons.schedule_rounded,
          color: p.warning,
        ),
      ],
    );
  }

  Widget _metric(NovaPalette p, String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: NovaTextStyles.caption(p.textDim)),
          const SizedBox(height: 2),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: NovaTextStyles.number(13, p.text)),
        ],
      ),
    );
  }
}
