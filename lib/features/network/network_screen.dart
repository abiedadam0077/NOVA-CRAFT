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
    this.activeRun = false,
  });

  final ServerConfig config;
  final bool active;

  /// Address the Playit agent reported in `status.json`. Shown when the config
  /// has no manual override — it is never invented by the app.
  final String reportedAddress;

  /// Latest runner snapshot, used for the real tunnel name/protocol/reasons.
  final ServerRuntime? runtime;
  final bool activeRun;

  @override
  State<NetworkView> createState() => _NetworkViewState();
}

class _NetworkViewState extends State<NetworkView> {
  late ServerConfig _config;
  final TextEditingController _address = TextEditingController();
  final TextEditingController _secret = TextEditingController();

  bool _testing = false;
  bool _saving = false;
  bool _addressDirty = false;
  bool _linkingPlayit = false;
  bool _secretPresent = false;
  bool _localSecretPresent = false;
  bool _checkedSecret = false;
  String? _secretError;
  PingResult? _result;
  DateTime? _testedAt;
  String? _testError;
  bool _checkingPlayit = false;
  bool _savingTunnel = false;
  String? _selectedTunnelId;
  PlayitAgentState? _playitState;
  String? _playitError;

  @override
  void initState() {
    super.initState();
    _config = widget.config;
    _selectedTunnelId = _config.playitTunnelId.isEmpty ? null : _config.playitTunnelId;
    _address.text = _config.connectionHostPort.isEmpty ? widget.reportedAddress : _config.connectionHostPort;
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkSecret());
  }

  @override
  void didUpdateWidget(covariant NetworkView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool serverChanged = oldWidget.config.repoFull != widget.config.repoFull;
    final bool configChanged = oldWidget.config.playitAddress != widget.config.playitAddress ||
        oldWidget.config.playitTunnelId != widget.config.playitTunnelId;
    if (serverChanged || configChanged) {
      _config = widget.config;
      _selectedTunnelId = _config.playitTunnelId.isEmpty ? null : _config.playitTunnelId;
    }
    if ((serverChanged || oldWidget.reportedAddress != widget.reportedAddress || oldWidget.config.playitAddress != widget.config.playitAddress) &&
        !_addressDirty) {
      _address.text = _config.connectionHostPort.isEmpty ? widget.reportedAddress : _config.connectionHostPort;
    }
  }

  @override
  void dispose() {
    _address.dispose();
    _secret.dispose();
    super.dispose();
  }

  String get _effectiveAddress {
    final String configured = _config.connectionHostPort;
    if (configured.isNotEmpty) return configured;
    return widget.reportedAddress.replaceFirst('tcp://', '').replaceFirst('udp://', '').trim();
  }

  String get _host => _effectiveAddress.isEmpty
      ? ''
      : Validation.parseHostPort(_effectiveAddress, _config.localPort).host;

  Future<void> _checkSecret() async {
    final AppState state = AppScope.read(context);
    bool localPresent = false;
    try {
      final String? local = await state.store.playitSecret();
      localPresent = local != null && local.isNotEmpty;
      final List<String> names = await state.api.listSecretNames(_config.repoOwner, _config.repoName);
      if (!mounted) return;
      setState(() {
        _secretPresent = names.contains('PLAYIT_SECRET_KEY');
        _localSecretPresent = localPresent;
        _checkedSecret = true;
        _secretError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _localSecretPresent = localPresent;
        _checkedSecret = true;
        _secretError = Fmt.error(error);
      });
    }
  }

  Future<void> _saveAddress() async {
    final String value = _address.text.trim();
    if (value.isNotEmpty && !Validation.parseHostPort(value, _config.localPort).isValid) {
      showNovaToast(context, L10n.t('addressInvalid'), kind: ToastKind.warning);
      return;
    }
    setState(() => _saving = true);
    try {
      final AppState state = AppScope.read(context);
      final ServerConfig next = _config.copyWith(playitAddress: _address.text.trim());
      await Provisioner.updateConfig(state.api, next);
      state.upsertServer(next);
      if (!mounted) return;
      setState(() {
        _config = next;
        _addressDirty = false;
        _address.text = next.connectionHostPort;
      });
      showNovaToast(context, L10n.t('addressSaved'), kind: ToastKind.success);
    } catch (error) {
      if (!mounted) return;
      showNovaToast(context, Fmt.error(error), kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _unlinkPlayit() async {
    final bool ok = await showNovaConfirm(
      context,
      title: L10n.t('unlinkPlayit'),
      body: L10n.t('unlinkPlayitConfirm'),
      confirmLabel: L10n.t('unlinkPlayit'),
      icon: Icons.link_off_rounded,
    );
    if (!ok || !mounted) return;
    final AppState state = AppScope.read(context);
    try {
      await state.api.deleteSecret(_config.repoOwner, _config.repoName, 'PLAYIT_SECRET_KEY');
      await state.forgetPlayitSecret();
      if (!mounted) return;
      setState(() {
        _secretPresent = false;
        _localSecretPresent = false;
        _checkedSecret = true;
      });
      showNovaToast(context, L10n.t('playitUnlinked'), kind: ToastKind.success);
    } catch (error) {
      if (!mounted) return;
      showNovaToast(context, Fmt.error(error), kind: ToastKind.error);
    }
  }

  Future<void> _linkPlayit() async {
    final AppState state = AppScope.read(context);
    final String? stored = await state.store.playitSecret();
    if (!mounted) return;
    final String candidate = _secret.text.trim().isNotEmpty ? _secret.text.trim() : (stored ?? '').trim();
    if (!Validation.validPlayitSecret(candidate)) {
      setState(() => _secretError = L10n.t('playitSecretInvalid'));
      return;
    }
    setState(() {
      _linkingPlayit = true;
      _secretError = null;
    });
    try {
      // Saving a GitHub Secret is deliberately independent from checking the
      // live Agent. The next server workflow starts the Agent; connectivity is
      // then reported by status.json and can be checked from this screen.
      await state.installPlayitSecret(_config, provided: candidate);
      if (!mounted) return;
      _secret.clear();
      setState(() {
        _secretPresent = true;
        _localSecretPresent = true;
        _checkedSecret = true;
      });
      showNovaToast(context, L10n.t('playitLinked'), kind: ToastKind.success);
    } catch (error) {
      if (mounted) setState(() => _secretError = Fmt.error(error));
    } finally {
      if (mounted) setState(() => _linkingPlayit = false);
    }
  }

  Future<void> _test() async {
    final bool bedrock = _config.isBedrock;
    final HostPort parsed = Validation.parseHostPort(
      _address.text,
      bedrock ? _config.playitBedrockPort : _config.playitJavaPort,
    );
    if (!parsed.isValid) {
      showNovaToast(context, L10n.t('noAddressConfigured'), kind: ToastKind.warning);
      return;
    }
    setState(() {
      _testing = true;
      _testError = null;
      _result = null;
    });
    try {
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
      final PlayitAgentState result = await state.inspectPlayit();
      if (!mounted) return;
      setState(() {
        if (result.ok) {
          _playitState = result;
          final List<PlayitTunnel> matches = result.tunnelsFor(bedrock: _config.isBedrock);
          final String configuredId = _config.playitTunnelId;
          if (matches.any((PlayitTunnel tunnel) => tunnel.id == _selectedTunnelId) && _selectedTunnelId != null) {
            // Keep the user's unsaved selection while refreshing.
          } else if (matches.any((PlayitTunnel tunnel) => tunnel.id == configuredId) && configuredId.isNotEmpty) {
            _selectedTunnelId = configuredId;
          } else {
            _selectedTunnelId = null;
          }
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

  List<PlayitTunnel> get _matchingPlayitTunnels =>
      _playitState?.tunnelsFor(bedrock: _config.isBedrock) ?? <PlayitTunnel>[];

  List<PlayitTunnel> get _selectablePlayitTunnels =>
      _matchingPlayitTunnels.where((PlayitTunnel tunnel) => tunnel.id.isNotEmpty).toList();

  Widget _playitTunnelPicker() {
    final p = context.nova;
    final List<PlayitTunnel> matches = _matchingPlayitTunnels;
    final List<PlayitTunnel> selectable = _selectablePlayitTunnels;
    final bool dirty = (_selectedTunnelId ?? '') != _config.playitTunnelId;
    if (matches.isEmpty) {
      final PlayitAgentState? state = _playitState;
      final String body = state == null
          ? L10n.t('playitNoMatchingTunnel')
          : (state.tunnels.isEmpty
              ? L10n.t('playitNoTunnelsYet')
              : (state.hasUnsupportedTunnels(bedrock: _config.isBedrock)
                  ? L10n.t('playitTunnelTypeUnsupported')
                  : L10n.t('playitNoMatchingTunnel')));
      return InfoBanner(
        body: body,
        icon: Icons.info_outline_rounded,
        color: p.warning,
        dense: true,
      );
    }
    if (selectable.length > 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          NovaDropdown<String>(
            label: L10n.t('selectPlayitTunnel'),
            value: _selectedTunnelId,
            items: selectable.map((PlayitTunnel tunnel) {
              final String title = tunnel.name.isEmpty ? tunnel.id : tunnel.name;
              final String address = tunnel.address.isEmpty ? L10n.t('playitAwaitingAddress') : tunnel.address;
              return DropdownMenuItem<String>(
                value: tunnel.id,
                child: Text('$title · $address', maxLines: 1, overflow: TextOverflow.ellipsis),
              );
            }).toList(),
            onChanged: (String? value) => setState(() => _selectedTunnelId = value),
          ),
          if (dirty) ...<Widget>[
            const SizedBox(height: 8),
            NovaButton(
              label: L10n.t('saveChanges'),
              icon: Icons.save_rounded,
              size: NovaButtonSize.compact,
              loading: _savingTunnel,
              onPressed: _savingTunnel ? null : _saveTunnelSelection,
            ),
          ],
        ],
      );
    }
    if (matches.length > 1 && selectable.length < matches.length) {
      return InfoBanner(
        body: L10n.t('playitTunnelIdMissing'),
        icon: Icons.warning_amber_rounded,
        color: p.warning,
        dense: true,
      );
    }
    final PlayitTunnel only = matches.single;
    if (only.id.isEmpty) {
      return InfoBanner(
        body: L10n.t('playitTunnelIdMissing'),
        icon: Icons.warning_amber_rounded,
        color: p.warning,
        dense: true,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        InfoRow(
          label: L10n.t('selectedPlayitTunnel'),
          value: only.address.isEmpty ? only.name : only.address,
          monospace: only.address.isNotEmpty,
        ),
        if (dirty) ...<Widget>[
          const SizedBox(height: 8),
          NovaButton(
            label: L10n.t('saveChanges'),
            icon: Icons.save_rounded,
            size: NovaButtonSize.compact,
            loading: _savingTunnel,
            onPressed: _savingTunnel ? null : _saveTunnelSelection,
          ),
        ],
      ],
    );
  }

  Future<void> _saveTunnelSelection() async {
    if (_savingTunnel) return;
    setState(() => _savingTunnel = true);
    try {
      final AppState state = AppScope.read(context);
      final ServerConfig next = _config.copyWith(playitTunnelId: _selectedTunnelId ?? '');
      await Provisioner.updateConfig(state.api, next);
      state.upsertServer(next);
      if (!mounted) return;
      setState(() => _config = next);
      showNovaToast(context, L10n.t('playitTunnelSavedNextCycle'), kind: ToastKind.success);
    } catch (error) {
      if (!mounted) return;
      showNovaToast(context, Fmt.error(error), kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _savingTunnel = false);
    }
  }

  Future<void> _reconnect() async {
    final bool ok = await showNovaConfirm(
      context,
      title: L10n.t(widget.activeRun ? 'reconnect' : 'playitStartServerAgent'),
      body: L10n.t(widget.activeRun ? 'restartConfirmBody' : 'playitStartServerConfirm'),
      confirmLabel: L10n.t(widget.activeRun ? 'reconnect' : 'playitStartServerAgent'),
      icon: Icons.sync_rounded,
    );
    if (!ok || !mounted) return;
    try {
      final AppState state = AppScope.read(context);
      await Provisioner.restartServer(state.api, _config, activeRun: widget.activeRun);
      if (!mounted) return;
      showNovaToast(context, L10n.t('actionQueued'), kind: ToastKind.success);
    } catch (error) {
      if (!mounted) return;
      showNovaToast(context, Fmt.error(error), kind: ToastKind.error);
    }
  }

  String _agentStatusLabel(ServerRuntime runtime) {
    switch (runtime.agentStatus) {
      case 'not_started':
        return L10n.t('playitAgentNotStarted');
      case 'starting':
        return L10n.t('playitAgentStarting');
      case 'connected':
        return runtime.phase == 'stopped' ? L10n.t('playitAgentStopped') : L10n.t('playitAgentConnected');
      case 'failed':
        return L10n.t('playitAgentFailed');
      case 'stopped':
        return L10n.t('playitAgentStopped');
      default:
        return L10n.t('unknown');
    }
  }

  String _tunnelStatusLabel(ServerRuntime runtime) {
    switch (runtime.tunnelStatus) {
      case 'connected':
        return runtime.online ? L10n.t('playitConnectionReady') : L10n.t('tunnelUnknown');
      case 'allocated':
      case 'connecting':
        return L10n.t('playitTunnelConnecting');
      case 'missing':
      case 'not_created':
        return L10n.t('playitTunnelNotCreated');
      case 'unsupported':
        return L10n.t('playitTunnelTypeUnsupported');
      case 'address_unavailable':
        return L10n.t('playitTunnelAddressUnavailable');
      case 'server_port_not_listening':
        return L10n.t('playitServerPortNotListening');
      case 'origin_mismatch':
        return L10n.t('playitTunnelOriginMismatch');
      case 'selection_required':
        return L10n.t('playitTunnelSelectionRequired');
      case 'disabled':
        return L10n.t('tunnelInactive');
      case 'error':
        return L10n.t('playitTunnelError');
      default:
        return L10n.t('tunnelUnknown');
    }
  }

  String? _agentDiagnosticLabel(ServerRuntime runtime) {
    switch (runtime.agentDiagnostic) {
      case 'invalid_secret':
      case 'invalid_secret_format':
        return L10n.t('playitAgentBadSecret');
      case 'network_unreachable':
        return L10n.t('playitAgentNetworkFailure');
      case 'account_agent_limit':
        return L10n.t('playitAgentAccountLimit');
      case 'agent_download_failed':
      case 'agent_checksum_failed':
        return L10n.t('playitAgentDownloadFailure');
      case 'secure_temp_directory_failed':
      case 'temp_directory_unavailable':
      case 'write_secret_failed':
      case 'write_api_config_failed':
      case 'create_log_failed':
      case 'secure_temp_files_failed':
        return L10n.t('playitAgentTempFileFailure');
      case 'process_exited':
        return L10n.t('playitAgentProcessExited');
      case 'startup_timeout':
        return L10n.t('playitAgentStillStarting');
      case 'secret_missing':
        return L10n.t('playitAgentNotStarted');
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    final bool configured = _host.isNotEmpty;
    final String displayAddress = _effectiveAddress;
    final String addressLabel = L10n.t(_config.isBedrock ? 'bedrockAddress' : 'javaAddress');
    final bool runnerReady = widget.runtime?.tunnelConnected == true && widget.runtime!.online;
    final bool online = _result?.online ?? runnerReady;
    final String stateLabel = !configured
        ? L10n.t('tunnelUnknown')
        : (online
            ? L10n.t('tunnelActive')
            : (_result == null && widget.runtime == null ? L10n.t('tunnelUnknown') : L10n.t('tunnelInactive')));
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
          title: L10n.t('connectionAddress'),
          icon: Icons.lan_rounded,
          actionLabel: _testing ? L10n.t('testing') : L10n.t('testConnection'),
          onAction: _testing ? null : _test,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              AddressPill(
                address: displayAddress.isEmpty ? L10n.t('noAddressYet') : displayAddress,
                label: addressLabel,
                compact: true,
                onCopy: displayAddress.isEmpty
                    ? null
                    : () {
                        Clipboard.setData(ClipboardData(text: displayAddress));
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
                helper: _addressDirty
                    ? L10n.t('addressManualHint')
                    : (_config.connectionHostPort.isNotEmpty
                        ? L10n.t('addressFromConfig')
                        : (widget.reportedAddress.isNotEmpty
                            ? L10n.t('addressReportedByPlayit')
                            : L10n.t('addressManualHint'))),
                onChanged: (_) => setState(() {
                  _addressDirty = true;
                  _result = null;
                  _testedAt = null;
                  _testError = null;
                }),
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
              if (!_secretPresent || !_localSecretPresent) ...[
                const SizedBox(height: 10),
                NovaField(
                  label: L10n.t('playitKeyLabel'),
                  controller: _secret,
                  hint: 'SECRET_KEY',
                  obscure: true,
                  prefixIcon: Icons.key_rounded,
                  helper: _localSecretPresent ? L10n.t('playitStoredUse') : L10n.t('playitLinkInstructions'),
                  errorText: _secretError,
                ),
                const SizedBox(height: 10),
                NovaButton(
                  label: _linkingPlayit ? L10n.t('loading') : L10n.t('saveAsSecret'),
                  icon: Icons.lock_rounded,
                  loading: _linkingPlayit,
                  onPressed: _linkingPlayit ? null : _linkPlayit,
                ),
                const SizedBox(height: 10),
                Text(L10n.t('playitLinkInstructions'), style: NovaTextStyles.caption(p.textMuted)),
              ],
              if (_secretPresent) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: NovaButton(
                        label: L10n.t('openPlayitDashboard'),
                        size: NovaButtonSize.compact,
                        variant: NovaButtonVariant.secondary,
                        onPressed: () => launchUrl(Uri.parse(AppConfig.playitDashboard), mode: LaunchMode.externalApplication),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: NovaButton(
                        label: L10n.t('unlinkPlayit'),
                        size: NovaButtonSize.compact,
                        variant: NovaButtonVariant.ghost,
                        onPressed: _unlinkPlayit,
                      ),
                    ),
                  ],
                ),
              ],
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
                    label: L10n.t(widget.activeRun ? 'reconnect' : 'playitStartServerAgent'),
                    icon: widget.activeRun ? Icons.sync_rounded : Icons.play_arrow_rounded,
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
                  label: L10n.t('playitSecretStatus'),
                  value: widget.runtime!.playitSecretStatus == 'saved'
                      ? L10n.t('playitSecretSaved')
                      : (widget.runtime!.playitSecretStatus == 'missing'
                          ? L10n.t('playitSecretMissingFromRun')
                          : L10n.t('unknown')),
                  valueColor: widget.runtime!.playitSecretStatus == 'saved' ? p.successBright : p.warning,
                ),
                InfoRow(
                  label: L10n.t('playitAgentStatus'),
                  value: _agentStatusLabel(widget.runtime!),
                  valueColor: widget.runtime!.agentStatus == 'connected'
                      ? p.successBright
                      : (widget.runtime!.agentStatus == 'failed' ? p.danger : p.warning),
                ),
                InfoRow(
                  label: L10n.t('playitTunnelStatus'),
                  value: _tunnelStatusLabel(widget.runtime!),
                  valueColor: widget.runtime!.tunnelConnected && widget.runtime!.online
                      ? p.successBright
                      : (widget.runtime!.tunnelStatus == 'error' || widget.runtime!.tunnelStatus == 'unsupported'
                          ? p.danger
                          : p.warning),
                ),
                InfoRow(
                  label: L10n.t('playitServerPortStatus'),
                  value: widget.runtime!.serverPortStatus == 'listening'
                      ? L10n.t('playitServerPortListening')
                      : (widget.runtime!.serverPortStatus == 'not_listening'
                          ? L10n.t('playitServerPortNotListening')
                          : L10n.t('unknown')),
                  valueColor: widget.runtime!.serverPortStatus == 'listening' ? p.successBright : p.warning,
                ),
                if (widget.runtime!.gamePort != null)
                  InfoRow(label: L10n.t('playitGamePort'), value: '${widget.runtime!.gamePort}', monospace: true),
                if (widget.runtime!.tunnelName.isNotEmpty)
                  InfoRow(label: L10n.t('playitTunnelName'), value: widget.runtime!.tunnelName),
                if (widget.runtime!.tunnelProtocol.isNotEmpty)
                  InfoRow(label: L10n.t('playitTunnelProtocol'), value: widget.runtime!.tunnelProtocol, monospace: true),
                if (widget.runtime!.agentId.isNotEmpty)
                  InfoRow(label: L10n.t('playitAgentId'), value: widget.runtime!.agentId, monospace: true),
                if (widget.runtime!.tunnelLocalIp.isNotEmpty || widget.runtime!.tunnelLocalPort != null)
                  InfoRow(
                    label: L10n.t('playitTunnelLocalOrigin'),
                    value: '${widget.runtime!.tunnelLocalIp}${widget.runtime!.tunnelLocalPort == null ? '' : ':${widget.runtime!.tunnelLocalPort}'}',
                    monospace: true,
                  ),
                if (_agentDiagnosticLabel(widget.runtime!) != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(_agentDiagnosticLabel(widget.runtime!)!, style: NovaTextStyles.caption(p.warning)),
                  ),
                for (final String reason in widget.runtime!.tunnelOfflineReasons)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      L10n.f('playitTunnelDisabled', <String, String>{'reason': reason}),
                      style: NovaTextStyles.caption(p.warning),
                    ),
                  ),
                if (_secretPresent && widget.runtime!.agentStatus == 'starting')
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: InfoBanner(
                      body: L10n.t('playitAgentStillStarting'),
                      icon: Icons.info_outline_rounded,
                      color: p.warning,
                      dense: true,
                    ),
                  )
                else if (_secretPresent &&
                    widget.runtime!.agentStatus != 'connected' && widget.runtime!.agentStatus != 'failed')
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: InfoBanner(
                      body: L10n.t('playitStartServerAgentHint'),
                      icon: Icons.info_outline_rounded,
                      color: p.warning,
                      dense: true,
                    ),
                  ),
                if (widget.runtime!.agentLogTail.trim().isNotEmpty)
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: EdgeInsets.zero,
                    title: Text(L10n.t('playitAgentLogTitle'), style: NovaTextStyles.caption(p.textDim)),
                    children: <Widget>[
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 200),
                        child: SingleChildScrollView(
                          child: SelectableText(
                            widget.runtime!.agentLogTail,
                            style: NovaTextStyles.mono(11, p.textDim),
                          ),
                        ),
                      ),
                    ],
                  ),
              ] else if (_secretPresent) ...<Widget>[
                const SizedBox(height: 8),
                InfoBanner(
                  body: L10n.t('playitStartServerAgentHint'),
                  icon: Icons.info_outline_rounded,
                  color: p.warning,
                  dense: true,
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
                      const SizedBox(height: 8),
                      _playitTunnelPicker(),
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
