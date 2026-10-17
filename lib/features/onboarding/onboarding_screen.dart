import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../core/strings.dart';
import '../../design/theme.dart';
import '../../design/tokens.dart';
import '../../design/widgets/background.dart';
import '../../design/widgets/brand.dart';
import '../../design/widgets/buttons.dart';
import '../../design/widgets/feedback.dart';
import '../../design/widgets/surfaces.dart';
import '../../state/app_state.dart';
import '../auth/device_flow_card.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _page = 0;
  bool _playitOpened = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    setState(() => _page = page);
    _controller.animateToPage(
      page,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppState state = AppScope.of(context);
    final p = context.nova;
    return Scaffold(
      backgroundColor: p.bg,
      body: AuroraBackground(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(NovaSpace.page, 12, NovaSpace.page, 4),
                child: Row(
                  children: <Widget>[
                    if (_page > 0)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 10),
                        child: NovaIconButton(
                          icon: Directionality.of(context) == TextDirection.rtl
                              ? Icons.arrow_forward_rounded
                              : Icons.arrow_back_rounded,
                          size: 36,
                          iconSize: 18,
                          onTap: () => _goTo(_page - 1),
                        ),
                      ),
                    const BrandLockup(markSize: 30, fontSize: 14, letterSpacing: 2),
                    const Spacer(),
                    TextButton(
                      onPressed: () => state.setOnboarded(true),
                      style: TextButton.styleFrom(
                        foregroundColor: p.textMuted,
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(L10n.t('skipForNow'), style: NovaTextStyles.small(p.textMuted)),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _controller,
                  onPageChanged: (int page) => setState(() => _page = page),
                  physics: const BouncingScrollPhysics(),
                  children: <Widget>[
                    _WelcomePage(onStart: () => _goTo(1)),
                    _GithubPage(
                      onAuthorized: () async {
                        _goTo(2);
                      },
                    ),
                    _PlayitPage(
                      playitOpened: _playitOpened,
                      onOpen: () async {
                        setState(() => _playitOpened = true);
                        await launchUrl(Uri.parse(AppConfig.playitDashboard), mode: LaunchMode.externalApplication);
                      },
                      onContinue: () => _goTo(3),
                    ),
                    _SuccessPage(
                      state: state,
                      onFinish: () => state.setOnboarded(true),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(NovaSpace.page, 10, NovaSpace.page, 22),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List<Widget>.generate(4, (int i) {
                    final bool active = i == _page;
                    return AnimatedContainer(
                      duration: NovaDurations.normal,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: active ? 26 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        gradient: active ? NovaGradients.primary : null,
                        color: active ? null : p.strokeStrong.withValues(alpha: 0.35),
                        borderRadius: NovaRadii.rPill,
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WelcomePage extends StatelessWidget {
  const _WelcomePage({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(NovaSpace.page, 0, NovaSpace.page, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                height: math.min(constraints.maxHeight * 0.42, 320),
                child: ClipRRect(
                  borderRadius: NovaRadii.rXl,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      Image.asset('assets/images/hero_castle.jpg', fit: BoxFit.cover, alignment: Alignment.center),
                      const DecoratedBox(decoration: BoxDecoration(gradient: NovaGradients.heroScrim)),
                      const Positioned.fill(child: ParticleField(count: 18)),
                      PositionedDirectional(
                        start: 16,
                        bottom: 14,
                        child: BrandBadge(label: 'Minecraft', color: p.cyan, icon: Icons.view_in_ar_rounded),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(L10n.t('welcomeTitle'), style: NovaTextStyles.display(30, p.text)),
              const SizedBox(height: 10),
              Text(L10n.t('welcomeBody'), style: NovaTextStyles.body(p.textMuted)),
              const SizedBox(height: 20),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _FeatureTile(
                      icon: Icons.dns_rounded,
                      title: L10n.t('featureServersTitle'),
                      body: L10n.t('featureServersBody'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _FeatureTile(
                      icon: Icons.hub_rounded,
                      title: L10n.t('featurePlayitTitle'),
                      body: L10n.t('featurePlayitBody'),
                      accent: p.violet,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              NovaButton(
                label: L10n.t('getStarted'),
                icon: Icons.arrow_forward_rounded,
                onPressed: onStart,
                height: 56,
              ),
              const SizedBox(height: 6),
              Center(
                child: TextButton(
                  onPressed: onStart,
                  style: TextButton.styleFrom(foregroundColor: p.textMuted),
                  child: Text(L10n.t('alreadyHaveAccount'), style: NovaTextStyles.smallStrong(p.textMuted)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({required this.icon, required this.title, required this.body, this.accent});

  final IconData icon;
  final String title;
  final String body;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    final Color c = accent ?? p.primaryBright;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        gradient: NovaGradients.card(p),
        borderRadius: NovaRadii.rLg,
        border: Border.all(color: p.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.14),
              borderRadius: NovaRadii.rSm,
              border: Border.all(color: c.withValues(alpha: 0.3)),
            ),
            child: Icon(icon, size: 17, color: c),
          ),
          const SizedBox(height: 10),
          Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: NovaTextStyles.smallStrong(p.text)),
          const SizedBox(height: 3),
          Text(body, maxLines: 2, overflow: TextOverflow.ellipsis, style: NovaTextStyles.small(p.textDim).copyWith(fontSize: 11)),
        ],
      ),
    );
  }
}

class _GithubPage extends StatelessWidget {
  const _GithubPage({required this.onAuthorized});

  final Future<void> Function() onAuthorized;

  @override
  Widget build(BuildContext context) {
    final AppState state = AppScope.of(context);
    final p = context.nova;
    return ListView(
      padding: const EdgeInsets.fromLTRB(NovaSpace.page, 10, NovaSpace.page, 20),
      children: <Widget>[
        Center(
          child: Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              borderRadius: NovaRadii.rXl,
              gradient: RadialGradient(
                colors: <Color>[p.primary.withValues(alpha: 0.22), p.bg.withValues(alpha: 0.0)],
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                const LogoMark(size: 120, glow: false),
                Positioned(
                  bottom: 14,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: p.surface,
                      borderRadius: NovaRadii.rPill,
                      border: Border.all(color: p.stroke),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(Icons.code_rounded, size: 12, color: p.text),
                        const SizedBox(width: 5),
                        Text('GitHub', style: NovaTextStyles.smallStrong(p.text).copyWith(fontSize: 10.5)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Center(child: Text(L10n.t('signInTitle'), textAlign: TextAlign.center, style: NovaTextStyles.display(25, p.text))),
        const SizedBox(height: 8),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              L10n.t('signInSubtitle'),
              textAlign: TextAlign.center,
              style: NovaTextStyles.small(p.textMuted),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: p.cardSoft,
            borderRadius: NovaRadii.rLg,
            border: Border.all(color: p.stroke),
          ),
          child: Column(
            children: <Widget>[
              PermissionRow(label: L10n.t('permissionRepos')),
              PermissionRow(label: L10n.t('permissionActions')),
              PermissionRow(label: L10n.t('permissionServers')),
              PermissionRow(label: L10n.t('permissionSecurity')),
            ],
          ),
        ),
        const SizedBox(height: 18),
        DeviceFlowCard(
          onAuthorized: (String access, String? refresh, int? expiresIn) async {
            await state.completeLogin(access, refresh, expiresIn);
            await onAuthorized();
          },
        ),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            Icon(Icons.shield_rounded, size: 14, color: p.textDim),
            const SizedBox(width: 7),
            Expanded(child: Text(L10n.t('githubPermissions'), style: NovaTextStyles.small(p.textDim))),
          ],
        ),
      ],
    );
  }
}

class _PlayitPage extends StatelessWidget {
  const _PlayitPage({required this.playitOpened, required this.onOpen, required this.onContinue});

  final bool playitOpened;
  final Future<void> Function() onOpen;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return ListView(
      padding: const EdgeInsets.fromLTRB(NovaSpace.page, 4, NovaSpace.page, 20),
      children: <Widget>[
        ArtBanner(asset: 'assets/images/art_network.jpg', height: 150, alignment: Alignment.center),
        const SizedBox(height: 20),
        Text(L10n.t('playitLinkTitle'), style: NovaTextStyles.display(25, p.text)),
        const SizedBox(height: 8),
        Text(L10n.t('playitLinkBody'), style: NovaTextStyles.body(p.textMuted)),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: NovaGradients.card(p),
            borderRadius: NovaRadii.rLg,
            border: Border.all(color: p.stroke),
          ),
          child: Column(
            children: <Widget>[
              _StepRow(index: 1, label: L10n.t('playitStep1'), color: p.primaryBright),
              _StepRow(index: 2, label: L10n.t('playitStep2'), color: p.cyan),
              _StepRow(index: 3, label: L10n.t('playitStep3'), color: p.violet),
              _StepRow(index: 4, label: L10n.t('playitStep4'), color: p.successBright, last: true),
            ],
          ),
        ),
        const SizedBox(height: 16),
        InfoBanner(
          title: L10n.t('playitKeyLabel'),
          body: L10n.t('playitKeyBody'),
          icon: Icons.key_rounded,
          color: p.violet,
        ),
        const SizedBox(height: 18),
        NovaButton(
          label: L10n.t('openPlayitDashboard'),
          icon: Icons.open_in_new_rounded,
          variant: NovaButtonVariant.secondary,
          height: 50,
          onPressed: onOpen,
        ),
        const SizedBox(height: 10),
        NovaButton(
          label: playitOpened ? L10n.t('continue') : L10n.t('skipForNow'),
          trailingIcon: Icons.arrow_forward_rounded,
          height: 54,
          onPressed: onContinue,
        ),
        const SizedBox(height: 10),
        Center(
          child: Text(
            L10n.t('playitSkippedNote'),
            textAlign: TextAlign.center,
            style: NovaTextStyles.small(p.textDim),
          ),
        ),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.index, required this.label, required this.color, this.last = false});

  final int index;
  final String label;
  final Color color;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: NovaRadii.rXs,
              border: Border.all(color: color.withValues(alpha: 0.34)),
            ),
            child: Text('$index', style: NovaTextStyles.number(13, color)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(label, style: NovaTextStyles.body(p.text)),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuccessPage extends StatefulWidget {
  const _SuccessPage({required this.state, required this.onFinish});

  final AppState state;
  final VoidCallback onFinish;

  @override
  State<_SuccessPage> createState() => _SuccessPageState();
}

class _SuccessPageState extends State<_SuccessPage> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return ListView(
      padding: const EdgeInsets.fromLTRB(NovaSpace.page, 10, NovaSpace.page, 20),
      children: <Widget>[
        SizedBox(
          height: 240,
          child: Center(
            child: ScaleTransition(
              scale: CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
              child: Container(
                width: 148,
                height: 148,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: <Color>[
                      p.success.withValues(alpha: 0.28),
                      p.success.withValues(alpha: 0.02),
                    ],
                  ),
                ),
                child: Center(
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: p.success.withValues(alpha: 0.16),
                      border: Border.all(color: p.success.withValues(alpha: 0.6), width: 2),
                      boxShadow: NovaShadows.glow(p.success, alpha: 0.4, blur: 34),
                    ),
                    child: Icon(Icons.check_rounded, size: 50, color: p.successBright),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Center(child: Text(L10n.t('accountsConnected'), style: NovaTextStyles.display(26, p.text))),
        const SizedBox(height: 8),
        Center(
          child: Text(
            L10n.t('accountsConnectedBody'),
            textAlign: TextAlign.center,
            style: NovaTextStyles.body(p.textMuted),
          ),
        ),
        const SizedBox(height: 22),
        _LinkedCard(
          icon: Icons.code_rounded,
          title: 'GitHub',
          subtitle: '@${widget.state.user?.login ?? ''}',
          status: L10n.t('connected'),
          ok: widget.state.user != null,
          accent: p.primaryBright,
        ),
        const SizedBox(height: 10),
        _LinkedCard(
          icon: Icons.hub_rounded,
          title: 'Playit.gg',
          subtitle: L10n.t('playitAccount'),
          status: L10n.t('notConfigured'),
          ok: false,
          accent: p.violet,
          neutral: true,
        ),
        const SizedBox(height: 24),
        NovaButton(
          label: L10n.t('continueToDashboard'),
          icon: Icons.arrow_forward_rounded,
          height: 56,
          onPressed: widget.onFinish,
        ),
      ],
    );
  }
}

class _LinkedCard extends StatelessWidget {
  const _LinkedCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.ok,
    required this.accent,
    this.neutral = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String status;
  final bool ok;
  final Color accent;
  final bool neutral;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: NovaGradients.card(p),
        borderRadius: NovaRadii.rLg,
        border: Border.all(color: neutral ? p.stroke : accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: NovaRadii.rSm,
              border: Border.all(color: accent.withValues(alpha: 0.3)),
            ),
            child: Icon(icon, size: 20, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: NovaTextStyles.bodyStrong(p.text)),
                const SizedBox(height: 2),
                Text(subtitle, style: NovaTextStyles.small(p.textDim)),
              ],
            ),
          ),
          Pill(
            label: status,
            tone: neutral ? PillTone.neutral : PillTone.success,
            icon: ok ? Icons.check_rounded : Icons.schedule_rounded,
          ),
        ],
      ),
    );
  }
}
