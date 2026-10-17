import 'package:flutter/material.dart';

import '../theme.dart';
import '../tokens.dart';

class LogoMark extends StatelessWidget {
  const LogoMark({super.key, this.size = 72, this.glow = true, this.asset = 'assets/brand/logo_mark.png'});

  final double size;
  final bool glow;
  final String asset;

  @override
  Widget build(BuildContext context) {
    final Widget image = Image.asset(
      asset,
      width: size,
      height: size,
      filterQuality: FilterQuality.high,
      isAntiAlias: true,
    );
    if (!glow) return image;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Container(
            width: size * 0.9,
            height: size * 0.9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: <Color>[
                  context.nova.primary.withValues(alpha: 0.28),
                  context.nova.primary.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
          image,
        ],
      ),
    );
  }
}

class BrandWordmark extends StatelessWidget {
  const BrandWordmark({
    super.key,
    this.fontSize = 26,
    this.gradient = NovaGradients.brand,
    this.color,
    this.letterSpacing = 3.4,
  });

  final double fontSize;
  final Gradient gradient;
  final Color? color;
  final double letterSpacing;

  @override
  Widget build(BuildContext context) {
    final TextStyle style = NovaTextStyles.brand(fontSize, Colors.white).copyWith(letterSpacing: letterSpacing);
    if (color != null) {
      return Text('NOVA CRAFT', style: style.copyWith(color: color));
    }
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (Rect bounds) => gradient.createShader(bounds),
      child: Text('NOVA CRAFT', style: style),
    );
  }
}

class BrandLockup extends StatelessWidget {
  const BrandLockup({
    super.key,
    this.markSize = 40,
    this.fontSize = 20,
    this.showTagline = false,
    this.letterSpacing = 2.6,
  });

  final double markSize;
  final double fontSize;
  final bool showTagline;
  final double letterSpacing;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        LogoMark(size: markSize, glow: false),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            BrandWordmark(fontSize: fontSize, letterSpacing: letterSpacing),
            if (showTagline)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'MINECRAFT SERVER MANAGER',
                  style: NovaTextStyles.caption(p.textDim).copyWith(letterSpacing: 1.6, fontSize: 7.5),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Full-bleed artwork with a tinted scrim, used for heroes and empty states.
class ArtBanner extends StatelessWidget {
  const ArtBanner({
    super.key,
    required this.asset,
    this.height = 200,
    this.radius = NovaRadii.rXl,
    this.child,
    this.alignment = Alignment.center,
    this.scrim = true,
    this.tint,
  });

  final String asset;
  final double height;
  final double radius;
  final Widget? child;
  final Alignment alignment;
  final bool scrim;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Image.asset(
              asset,
              fit: BoxFit.cover,
              alignment: alignment,
              filterQuality: FilterQuality.medium,
            ),
            if (scrim)
              const DecoratedBox(
                decoration: BoxDecoration(gradient: NovaGradients.heroScrim),
              ),
            if (tint != null)
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[tint!.withValues(alpha: 0.32), p.bg.withValues(alpha: 0.55)],
                  ),
                ),
              ),
            if (child != null) child!,
          ],
        ),
      ),
    );
  }
}

/// A small outline badge used for "BETA", "JAVA", "BEDROCK" etc.
class BrandBadge extends StatelessWidget {
  const BrandBadge({super.key, required this.label, this.color, this.icon});

  final String label;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final Color c = color ?? context.nova.primaryBright;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: NovaRadii.rXs,
        border: Border.all(color: c.withValues(alpha: 0.4), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 11, color: c),
            const SizedBox(width: 4),
          ],
          Text(
            label.toUpperCase(),
            style: NovaTextStyles.caption(c).copyWith(fontSize: 9.5, letterSpacing: 1.0),
          ),
        ],
      ),
    );
  }
}
