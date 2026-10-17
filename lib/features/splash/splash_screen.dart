import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../../design/theme.dart';
import '../../design/tokens.dart';
import '../../design/widgets/background.dart';
import '../../design/widgets/brand.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..forward();

  late final Animation<double> _markScale = Tween<double>(begin: 0.82, end: 1).animate(
    CurvedAnimation(parent: _controller, curve: const Interval(0, 0.65, curve: Curves.easeOutBack)),
  );
  late final Animation<double> _fade = CurvedAnimation(parent: _controller, curve: const Interval(0, 0.5, curve: Curves.easeOut));
  late final Animation<double> _copyFade = CurvedAnimation(parent: _controller, curve: const Interval(0.35, 1, curve: Curves.easeOut));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return Scaffold(
      backgroundColor: p.bg,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Image.asset(
            'assets/images/hero_castle.jpg',
            fit: BoxFit.cover,
            alignment: Alignment.center,
            filterQuality: FilterQuality.medium,
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[Color(0xB3070B18), Color(0xF2070B18), Color(0xFF070B18)],
                stops: <double>[0.0, 0.62, 1.0],
              ),
            ),
          ),
          const Positioned.fill(child: ParticleField(count: 30, color: Color(0xFF9BD4FF))),
          SafeArea(
            child: Column(
              children: <Widget>[
                const Spacer(flex: 3),
                AnimatedBuilder(
                  animation: _controller,
                  builder: (BuildContext context, Widget? child) {
                    return Opacity(
                      opacity: _fade.value,
                      child: Transform.scale(scale: _markScale.value, child: child),
                    );
                  },
                  child: Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      _GlowRing(animation: _controller),
                      const LogoMark(size: 128),
                    ],
                  ),
                ),
                const SizedBox(height: 26),
                AnimatedBuilder(
                  animation: _copyFade,
                  builder: (BuildContext context, Widget? child) {
                    return Opacity(
                      opacity: _copyFade.value,
                      child: Transform.translate(
                        offset: Offset(0, 12 * (1 - _copyFade.value)),
                        child: child,
                      ),
                    );
                  },
                  child: Column(
                    children: <Widget>[
                      const BrandWordmark(fontSize: 30, letterSpacing: 6.4),
                      const SizedBox(height: 10),
                      Text(
                        L10n.t('appTagline').toUpperCase(),
                        style: NovaTextStyles.caption(p.textMuted).copyWith(letterSpacing: 3.2, fontSize: 9.5),
                      ),
                    ],
                  ),
                ),
                const Spacer(flex: 2),
                AnimatedBuilder(
                  animation: _copyFade,
                  builder: (BuildContext context, Widget? child) {
                    return Opacity(opacity: _copyFade.value, child: child);
                  },
                  child: Column(
                    children: <Widget>[
                      SizedBox(
                        width: 168,
                        child: ClipRRect(
                          borderRadius: NovaRadii.rPill,
                          child: const LinearProgressIndicator(
                            minHeight: 3,
                            backgroundColor: Color(0x33FFFFFF),
                            color: Color(0xFF5B9CFF),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          const _SpinnerDots(),
                          const SizedBox(width: 10),
                          Text(L10n.t('loadingAdventure'), style: NovaTextStyles.small(p.textMuted)),
                        ],
                      ),
                      const SizedBox(height: 30),
                      Text(
                        '${L10n.t('managedByGithub')} · v1.0.0',
                        style: NovaTextStyles.caption(p.textDim).copyWith(letterSpacing: 1.2),
                      ),
                      const SizedBox(height: 22),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowRing extends StatelessWidget {
  const _GlowRing({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (BuildContext context, Widget? child) {
        final double t = animation.value;
        return Container(
          width: 210 + 26 * math.sin(t * math.pi * 2),
          height: 210 + 26 * math.sin(t * math.pi * 2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: <Color>[
                const Color(0xFF4F8DFF).withValues(alpha: 0.30 * t),
                const Color(0xFF4F8DFF).withValues(alpha: 0.0),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SpinnerDots extends StatefulWidget {
  const _SpinnerDots();

  @override
  State<_SpinnerDots> createState() => _SpinnerDotsState();
}

class _SpinnerDotsState extends State<_SpinnerDots> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List<Widget>.generate(3, (int i) {
            final double phase = (_controller.value - i * 0.18) % 1.0;
            final double opacity = 0.25 + 0.75 * (0.5 + 0.5 * math.sin(phase * math.pi * 2));
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: p.primaryBright.withValues(alpha: opacity),
                  shape: BoxShape.circle,
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
