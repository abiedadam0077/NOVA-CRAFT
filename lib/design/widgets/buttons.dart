import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import '../tokens.dart';

enum NovaButtonVariant { primary, secondary, danger, ghost, success }

class NovaButton extends StatelessWidget {
  const NovaButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.trailingIcon,
    this.loading = false,
    this.expand = true,
    this.height = 54,
    this.variant = NovaButtonVariant.primary,
    this.size = NovaButtonSize.regular,
    this.badge,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final IconData? trailingIcon;
  final bool loading;
  final bool expand;
  final double height;
  final NovaButtonVariant variant;
  final NovaButtonSize size;
  final Widget? badge;

  bool get _enabled => onPressed != null && !loading;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    final bool small = size == NovaButtonSize.compact;

    Color textColor = Colors.white;
    Gradient? gradient;
    Color? background;
    Color? borderColor;
    List<BoxShadow>? shadow;

    switch (variant) {
      case NovaButtonVariant.primary:
        gradient = NovaGradients.primary;
        shadow = _enabled ? NovaShadows.glow(p.indigo, alpha: p.isDark ? 0.42 : 0.28, blur: 24, y: 10) : null;
        break;
      case NovaButtonVariant.danger:
        gradient = NovaGradients.danger;
        shadow = _enabled ? NovaShadows.glow(p.danger, alpha: p.isDark ? 0.36 : 0.24, blur: 22, y: 9) : null;
        break;
      case NovaButtonVariant.success:
        gradient = NovaGradients.success;
        shadow = _enabled ? NovaShadows.glow(p.success, alpha: p.isDark ? 0.32 : 0.2, blur: 22, y: 9) : null;
        break;
      case NovaButtonVariant.secondary:
        background = p.cardSoft;
        borderColor = p.strokeStrong.withValues(alpha: 0.55);
        textColor = p.text;
        break;
      case NovaButtonVariant.ghost:
        background = Colors.transparent;
        textColor = p.primaryBright;
        break;
    }

    if (!_enabled) {
      textColor = p.textDim;
      gradient = null;
      if (variant == NovaButtonVariant.primary || variant == NovaButtonVariant.danger || variant == NovaButtonVariant.success) {
        background = p.cardHigh;
      }
      borderColor = p.stroke;
      shadow = null;
    }

    final double radius = small ? NovaRadii.md : NovaRadii.lg;
    final TextStyle labelStyle = NovaTextStyles.button(textColor).copyWith(
      fontSize: small ? 13.5 : 15,
    );

    Widget content = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (loading)
          SizedBox(
            width: small ? 14 : 17,
            height: small ? 14 : 17,
            child: CircularProgressIndicator(strokeWidth: 2, color: textColor),
          )
        else if (icon != null) ...<Widget>[
          Icon(icon, size: small ? 17 : 19, color: textColor),
          SizedBox(width: small ? 6 : 9),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: labelStyle,
          ),
        ),
        if (badge != null) ...<Widget>[const SizedBox(width: 8), badge!],
        if (trailingIcon != null) ...<Widget>[
          SizedBox(width: small ? 6 : 9),
          Icon(trailingIcon, size: small ? 16 : 18, color: textColor),
        ],
      ],
    );

    Widget button = Container(
      height: small ? (height * 0.72).clamp(38.0, 52.0).toDouble() : height,
      width: expand ? double.infinity : null,
      padding: EdgeInsets.symmetric(horizontal: small ? 14 : 20),
      decoration: BoxDecoration(
        gradient: gradient,
        color: gradient == null ? background : null,
        borderRadius: BorderRadius.circular(radius),
        border: borderColor != null ? Border.all(color: borderColor, width: 1) : null,
        boxShadow: shadow,
      ),
      child: Center(child: content),
    );

    if (gradient != null && _enabled) {
      button = Stack(
        children: <Widget>[
          button,
          // Inner top highlight gives the gradient a glassy, premium edge.
          Positioned(
            top: 1,
            left: 12,
            right: 12,
            height: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: <Color>[Colors.white.withValues(alpha: 0.0), Colors.white.withValues(alpha: 0.45), Colors.white.withValues(alpha: 0.0)],
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Semantics(
      button: true,
      enabled: _enabled,
      label: label,
      child: PressableScale(
        onTap: _enabled
            ? () {
                HapticFeedback.selectionClick();
                onPressed!();
              }
            : null,
        scale: 0.972,
        child: button,
      ),
    );
  }
}

enum NovaButtonSize { regular, compact }

class NovaIconButton extends StatelessWidget {
  const NovaIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.tooltip,
    this.size = 42,
    this.iconSize = 20,
    this.filled = false,
    this.accent,
    this.badge,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final double size;
  final double iconSize;
  final bool filled;
  final Color? accent;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    final Color color = accent ?? (filled ? p.text : p.textMuted);
    final Widget button = PressableScale(
      onTap: onTap,
      scale: 0.92,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: filled ? p.cardHigh.withValues(alpha: 0.9) : p.surface.withValues(alpha: 0.55),
          borderRadius: NovaRadii.rMd,
          border: Border.all(color: filled ? p.strokeStrong.withValues(alpha: 0.4) : p.stroke),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Icon(icon, size: iconSize, color: color),
            if (badge != null) Positioned(top: 9, right: 9, child: badge!),
          ],
        ),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

class NovaChip extends StatelessWidget {
  const NovaChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.icon,
    this.color,
    this.count,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  final Color? color;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    final Color accent = color ?? p.primaryBright;
    final Color bg = selected ? accent.withValues(alpha: p.isDark ? 0.18 : 0.12) : p.cardSoft;
    final Color border = selected ? accent.withValues(alpha: 0.6) : p.stroke;
    final Color fg = selected ? accent : p.textMuted;

    return PressableScale(
      onTap: onTap,
      scale: 0.95,
      child: AnimatedContainer(
        duration: NovaDurations.fast,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: NovaRadii.rPill,
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 6),
            ],
            Text(label, style: NovaTextStyles.smallStrong(fg)),
            if (count != null) ...<Widget>[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: fg.withValues(alpha: 0.16),
                  borderRadius: NovaRadii.rXs,
                ),
                child: Text('$count', style: NovaTextStyles.caption(fg).copyWith(fontSize: 9.5)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Segmented control with a sliding pill indicator.
class NovaSegmented extends StatelessWidget {
  const NovaSegmented({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
    this.icons,
    this.height = 44,
    this.accent,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  final List<IconData>? icons;
  final double height;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    final Color a = accent ?? p.primaryBright;
    return Container(
      height: height,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: p.isDark ? p.bgDeep.withValues(alpha: 0.85) : p.cardHigh,
        borderRadius: NovaRadii.rPill,
        border: Border.all(color: p.stroke),
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double itemWidth = constraints.maxWidth / labels.length;
          return Stack(
            children: <Widget>[
              AnimatedPositioned(
                duration: NovaDurations.normal,
                curve: Curves.easeOutCubic,
                left: itemWidth * index,
                top: 0,
                bottom: 0,
                width: itemWidth,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: <Color>[a.withValues(alpha: 0.95), a.withValues(alpha: 0.78)],
                    ),
                    borderRadius: NovaRadii.rPill,
                    boxShadow: NovaShadows.glow(a, alpha: 0.28, blur: 14, y: 4),
                  ),
                ),
              ),
              Row(
                children: List<Widget>.generate(labels.length, (int i) {
                  final bool selected = i == index;
                  final Color fg = selected ? Colors.white : p.textMuted;
                  return Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onChanged(i),
                      child: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            if (icons != null && i < icons!.length) ...<Widget>[
                              Icon(icons![i], size: 15, color: fg),
                              const SizedBox(width: 5),
                            ],
                            Flexible(
                              child: Text(
                                labels[i],
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: NovaTextStyles.smallStrong(fg),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          );
        },
      ),
    );
  }
}
