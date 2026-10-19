import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/strings.dart';
import '../../design/theme.dart';
import '../../design/tokens.dart';
import '../../design/widgets/background.dart';
import '../../design/widgets/brand.dart';
import '../../design/widgets/buttons.dart';
import '../../state/app_state.dart';

/// Three-slide first-run introduction. It introduces the product, then hands
/// over to GitHub sign-in — it never collects credentials or promises uptime.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pages = PageController();
  int _page = 0;

  static const List<String> _art = <String>[
    'assets/images/hero_castle.jpg',
    'assets/images/art_network.jpg',
    'assets/images/art_shield.jpg',
  ];

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    HapticFeedback.mediumImpact();
    await AppScope.read(context).setOnboarded(true);
  }

  void _next() {
    if (_page >= 2) {
      _finish();
      return;
    }
    _pages.nextPage(duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return Scaffold(
      backgroundColor: p.bg,
      body: AuroraBackground(
        child: SafeArea(
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(NovaSpace.page, 10, NovaSpace.page, 0),
                child: Row(
                  children: <Widget>[
                    const Expanded(child: BrandWordmark(fontSize: 15, letterSpacing: 3)),
                    TextButton(
                      onPressed: _finish,
                      style: TextButton.styleFrom(foregroundColor: p.textDim),
                      child: Text(L10n.t('skipIntro'), style: NovaTextStyles.small(p.textDim)),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pages,
                  itemCount: 3,
                  onPageChanged: (int value) => setState(() => _page = value),
                  itemBuilder: (BuildContext context, int index) {
                    final String title = L10n.t('onboardingTitle${index + 1}');
                    final String body = L10n.t('onboardingBody${index + 1}');
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(NovaSpace.page, 12, NovaSpace.page, 12),
                      physics: const BouncingScrollPhysics(),
                      children: <Widget>[
                        ArtBanner(
                          asset: _art[index],
                          height: 300,
                          alignment: Alignment.center,
                          radius: NovaRadii.rXl,
                        ),
                        const SizedBox(height: 26),
                        Text(
                          L10n.t('onboardingEyebrow${index + 1}'),
                          style: NovaTextStyles.caption(p.primaryBright),
                        ),
                        const SizedBox(height: 8),
                        Text(title, style: NovaTextStyles.display(30, p.text)),
                        const SizedBox(height: 12),
                        Text(body, style: NovaTextStyles.body(p.textMuted)),
                        const SizedBox(height: 18),
                        _Highlight(index: index),
                      ],
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(NovaSpace.page, 8, NovaSpace.page, 22),
                child: Column(
                  children: <Widget>[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List<Widget>.generate(3, (int i) {
                        final bool active = i == _page;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutCubic,
                          width: active ? 26 : 8,
                          height: 8,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            gradient: active ? NovaGradients.primary : null,
                            color: active ? null : p.strokeStrong.withValues(alpha: 0.4),
                            borderRadius: NovaRadii.rPill,
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 18),
                    NovaButton(
                      label: _page >= 2 ? L10n.t('continueWithGithub') : L10n.t('next'),
                      trailingIcon: _page >= 2
                          ? Icons.login_rounded
                          : (context.isRtl ? Icons.arrow_back_rounded : Icons.arrow_forward_rounded),
                      onPressed: _next,
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

/// A small, factual caption under each slide. No invented metrics.
class _Highlight extends StatelessWidget {
  const _Highlight({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    final IconData icon;
    switch (index) {
      case 0:
        icon = Icons.dns_rounded;
      case 1:
        icon = Icons.hub_rounded;
      default:
        icon = Icons.lock_rounded;
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.cardSoft,
        borderRadius: NovaRadii.rLg,
        border: Border.all(color: p.stroke),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: NovaGradients.primary,
              borderRadius: NovaRadii.rXs,
            ),
            child: Icon(icon, size: 17, color: p.primaryBright),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              L10n.t('onboardingNote${index + 1}'),
              style: NovaTextStyles.small(p.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}
