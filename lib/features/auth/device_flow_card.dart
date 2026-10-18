import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../core/formatters.dart';
import '../../core/models.dart';
import '../../core/strings.dart';
import '../../design/theme.dart';
import '../../design/tokens.dart';
import '../../design/widgets/buttons.dart';
import '../../design/widgets/feedback.dart';
import '../../state/app_state.dart';

/// GitHub App Device Flow. The user code is displayed in-app, the browser does
/// the authorization, and no password ever touches this app.
class DeviceFlowCard extends StatefulWidget {
  const DeviceFlowCard({super.key, required this.onAuthorized});

  final Future<void> Function(String accessToken, String? refreshToken, int? expiresIn) onAuthorized;

  @override
  State<DeviceFlowCard> createState() => _DeviceFlowCardState();
}

class _DeviceFlowCardState extends State<DeviceFlowCard> {
  DeviceCode? _code;
  bool _requesting = false;
  bool _polling = false;
  bool _success = false;
  String? _error;
  Timer? _timer;
  DateTime? _deadline;
  int _intervalSeconds = 5;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _requestCode() async {
    setState(() {
      _requesting = true;
      _error = null;
      _success = false;
    });
    try {
      final AppState state = AppScope.read(context);
      final DeviceCode code = await state.api.requestDeviceCode(AppConfig.githubClientId);
      if (!mounted) return;
      setState(() {
        _code = code;
        _intervalSeconds = code.interval < 5 ? 5 : code.interval;
        _deadline = DateTime.now().add(Duration(seconds: code.expiresIn));
      });
      _startPolling();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = Fmt.error(error));
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  void _startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: _intervalSeconds), (_) => _poll());
    // First check happens one interval later, matching GitHub's guidance.
  }

  Future<void> _poll() async {
    final DeviceCode? code = _code;
    if (code == null || _polling || !mounted) return;
    final DateTime? deadline = _deadline;
    if (deadline != null && DateTime.now().isAfter(deadline)) {
      _timer?.cancel();
      setState(() => _error = L10n.t('codeExpired'));
      return;
    }
    _polling = true;
    try {
      final AppState state = AppScope.read(context);
      final TokenPoll result = await state.api.pollDeviceToken(AppConfig.githubClientId, code.deviceCode);
      if (!mounted) return;
      switch (result.kind) {
        case TokenPollKind.success:
          _timer?.cancel();
          setState(() => _success = true);
          HapticFeedback.mediumImpact();
          await widget.onAuthorized(result.accessToken!, result.refreshToken, result.expiresIn);
          break;
        case TokenPollKind.pending:
          if (result.message == 'slow_down') {
            _intervalSeconds += 5;
            _startPolling();
          }
          break;
        case TokenPollKind.failure:
          _timer?.cancel();
          setState(() => _error = result.message == 'expired_token' ? L10n.t('codeExpired') : (result.message ?? L10n.t('errorGeneric')));
          break;
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = Fmt.error(error));
      _timer?.cancel();
    } finally {
      _polling = false;
    }
  }

  void _cancel() {
    _timer?.cancel();
    setState(() {
      _code = null;
      _error = null;
      _polling = false;
    });
  }

  Future<void> _openBrowser(String url) async {
    final Uri uri = Uri.parse(url);
    final bool ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      showNovaToast(context, L10n.t('errorGeneric'), kind: ToastKind.error);
    }
  }

  String _formatCode(String raw) {
    final String clean = raw.replaceAll(RegExp(r'\s'), '').toUpperCase();
    if (clean.length == 8) return '${clean.substring(0, 4)}-${clean.substring(4)}';
    return clean;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    if (_success) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: p.success.withValues(alpha: 0.12),
          borderRadius: NovaRadii.rLg,
          border: Border.all(color: p.success.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.check_circle_rounded, color: p.successBright),
            const SizedBox(width: 10),
            Expanded(
              child: Text(L10n.t('connected'), style: NovaTextStyles.bodyStrong(p.successBright)),
            ),
          ],
        ),
      );
    }

    if (_code == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          NovaButton(
            label: L10n.t('showCode'),
            icon: Icons.login_rounded,
            loading: _requesting,
            onPressed: _requesting ? null : _requestCode,
            height: 54,
          ),
          const SizedBox(height: 12),
          Text(
            L10n.t('deviceFlowIntro'),
            textAlign: TextAlign.center,
            style: NovaTextStyles.small(p.textDim),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 12),
            InlineError(message: _error!, onRetry: _requestCode),
          ],
        ],
      );
    }

    final DeviceCode code = _code!;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: NovaGradients.card(p),
        borderRadius: NovaRadii.rXl,
        border: Border.all(color: p.primary.withValues(alpha: 0.3)),
        boxShadow: NovaShadows.glow(p.primary, alpha: p.isDark ? 0.18 : 0.08, blur: 30),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(L10n.t('deviceCodeLabel').toUpperCase(), style: NovaTextStyles.caption(p.textMuted)),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: SelectableText(
                  _formatCode(code.userCode),
                  style: NovaTextStyles.monoStrong(28, p.text).copyWith(letterSpacing: 5),
                ),
              ),
              NovaIconButton(
                icon: Icons.content_copy_rounded,
                tooltip: L10n.t('copyCode'),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: code.userCode));
                  HapticFeedback.selectionClick();
                  showNovaToast(context, L10n.t('copied'), kind: ToastKind.success);
                },
              ),
            ],
          ),
          const SizedBox(height: 14),
          NovaButton(
            label: L10n.t('openGithub'),
            icon: Icons.open_in_new_rounded,
            height: 50,
            onPressed: () => _openBrowser(code.verificationUri),
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              const SizedBox(width: 18, height: 18, child: NovaLoader(size: 18, stroke: 2)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(L10n.t('waitingConfirmation'), style: NovaTextStyles.small(p.textMuted)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: _cancel,
              style: TextButton.styleFrom(
                foregroundColor: p.textDim,
                padding: const EdgeInsets.symmetric(horizontal: 0),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(L10n.t('cancel'), style: NovaTextStyles.small(p.textDim)),
            ),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 10),
            InlineError(message: _error!, onRetry: _requestCode),
          ],
        ],
      ),
    );
  }
}

/// Small permission row used on the sign-in screens.
class PermissionRow extends StatelessWidget {
  const PermissionRow({super.key, required this.label, this.icon = Icons.check_rounded});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: p.success.withValues(alpha: 0.14),
              borderRadius: NovaRadii.rXs,
              border: Border.all(color: p.success.withValues(alpha: 0.34)),
            ),
            child: Icon(icon, size: 13, color: p.successBright),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: NovaTextStyles.body(p.text))),
        ],
      ),
    );
  }
}
