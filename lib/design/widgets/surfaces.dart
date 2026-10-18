import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import '../tokens.dart';

/// Scales its child down slightly while pressed. Used by cards and buttons so
/// every touch in the app has the same physical feel.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.975,
    this.haptic = false,
    this.behavior = HitTestBehavior.opaque,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final bool haptic;
  final HitTestBehavior behavior;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  void _set(bool value) {
    if (!mounted) return;
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: widget.behavior,
      onTapDown: widget.onTap == null ? null : (_) => _set(true),
      onTapUp: widget.onTap == null ? null : (_) => _set(false),
      onTapCancel: widget.onTap == null ? null : () => _set(false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _pressed && widget.onTap != null ? widget.scale : 1.0,
        duration: NovaDurations.fast,
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

class NovaCard extends StatelessWidget {
  const NovaCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(NovaSpace.lg),
    this.onTap,
    this.onLongPress,
    this.accent,
    this.glow = false,
    this.borderRadius = NovaRadii.rLg,
    this.gradient,
    this.border,
    this.shadows,
    this.blurBackground = false,
    this.height,
    this.width,
    this.margin,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? accent;
  final bool glow;
  final BorderRadius borderRadius;
  final Gradient? gradient;
  final BoxBorder? border;
  final List<BoxShadow>? shadows;
  final bool blurBackground;
  final double? height;
  final double? width;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    final BorderRadius radius = borderRadius;
    final Gradient grad = gradient ?? NovaGradients.card(p);
    final BoxBorder brd = border ??
        Border.all(
          color: accent != null ? accent!.withValues(alpha: 0.35) : p.stroke,
          width: 1,
        );
    final List<BoxShadow> shadow = shadows ??
        (glow && accent != null
            ? NovaShadows.glow(accent!, alpha: p.isDark ? 0.28 : 0.18, blur: 30, y: 12)
            : NovaShadows.soft(p));

    Widget content = Container(
      margin: margin,
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: grad,
        borderRadius: radius,
        border: brd,
        boxShadow: shadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(gradient: grad, borderRadius: radius),
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            onLongPress: onLongPress,
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );

    if (blurBackground) {
      content = ClipRRect(borderRadius: radius, child: content);
    }
    return content;
  }
}

class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(NovaSpace.lg),
    this.borderRadius = NovaRadii.rLg,
    this.opacity = 0.72,
    this.border = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final double opacity;
  final bool border;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return ClipRRect(
      borderRadius: borderRadius,
      child: Container(
        decoration: BoxDecoration(
          color: p.surface.withValues(alpha: opacity),
          borderRadius: borderRadius,
          border: border ? Border.all(color: p.stroke) : null,
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.eyebrow,
    this.actionLabel,
    this.onAction,
    this.icon,
    this.padding = const EdgeInsets.only(bottom: NovaSpace.sm),
  });

  final String title;
  final String? subtitle;
  final String? eyebrow;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? icon;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: p.primary.withValues(alpha: 0.12),
                borderRadius: NovaRadii.rSm,
                border: Border.all(color: p.primary.withValues(alpha: 0.24)),
              ),
              child: Icon(icon, size: 18, color: p.primaryBright),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (eyebrow != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(eyebrow!.toUpperCase(), style: NovaTextStyles.caption(p.primaryBright)),
                  ),
                Text(title, style: NovaTextStyles.heading(17, p.text)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!, style: NovaTextStyles.small(p.textMuted)),
                  ),
              ],
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: p.primaryBright,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(actionLabel!, style: NovaTextStyles.smallStrong(p.primaryBright)),
                  const SizedBox(width: 2),
                  Icon(Icons.chevron_right_rounded, size: 16, color: p.primaryBright, textDirection: Directionality.of(context)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class SoftDivider extends StatelessWidget {
  const SoftDivider({super.key, this.height = 1, this.opacity = 1.0});

  final double height;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return Container(
      height: height,
      color: p.stroke.withValues(alpha: (p.isDark ? 0.075 : 0.06) * opacity),
    );
  }
}

class InfoBanner extends StatelessWidget {
  const InfoBanner({
    super.key,
    required this.body,
    this.title,
    this.icon = Icons.info_outline_rounded,
    this.color,
    this.actionLabel,
    this.onAction,
    this.dense = false,
  });

  final String body;
  final String? title;
  final IconData icon;
  final Color? color;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    final Color c = color ?? p.primaryBright;
    return Container(
      padding: EdgeInsets.all(dense ? 12 : 14),
      decoration: BoxDecoration(
        color: c.withValues(alpha: p.isDark ? 0.10 : 0.07),
        borderRadius: NovaRadii.rMd,
        border: Border.all(color: c.withValues(alpha: 0.24)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: c),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (title != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(title!, style: NovaTextStyles.smallStrong(c)),
                  ),
                Text(body, style: NovaTextStyles.small(p.textMuted)),
                if (actionLabel != null && onAction != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: GestureDetector(
                      onTap: onAction,
                      behavior: HitTestBehavior.opaque,
                      child: Text(actionLabel!, style: NovaTextStyles.smallStrong(c)),
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

/// A gradient hairline used to separate hero sections from content.
class GradientRule extends StatelessWidget {
  const GradientRule({super.key, this.height = 1});

  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return Container(
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            p.primary.withValues(alpha: 0.0),
            p.primary.withValues(alpha: 0.45),
            p.violet.withValues(alpha: 0.35),
            p.primary.withValues(alpha: 0.0),
          ],
        ),
      ),
    );
  }
}

/// Wraps a screen body with the app background and safe area handling.
class NovaPageBody extends StatelessWidget {
  const NovaPageBody({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: NovaSpace.page),
    this.bottomPadding = 120,
    this.safeTop = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double bottomPadding;
  final bool safeTop;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: safeTop,
      bottom: false,
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}

class HapticTap extends StatelessWidget {
  const HapticTap({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onTap!();
            },
      child: child,
    );
  }
}
