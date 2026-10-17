import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme.dart';
import '../tokens.dart';
import 'brand.dart';
import 'buttons.dart';

class NovaTopBar extends StatelessWidget {
  const NovaTopBar({
    super.key,
    this.title,
    this.subtitle,
    this.onBack,
    this.actions = const <Widget>[],
    this.showBrand = false,
    this.eyebrow,
    this.padding = const EdgeInsets.fromLTRB(NovaSpace.page, 10, NovaSpace.page, 10),
  });

  final String? title;
  final String? subtitle;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final bool showBrand;
  final String? eyebrow;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return Padding(
      padding: padding,
      child: Row(
        children: <Widget>[
          if (onBack != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 12),
              child: NovaIconButton(
                icon: Directionality.of(context) == TextDirection.rtl
                    ? Icons.arrow_forward_rounded
                    : Icons.arrow_back_rounded,
                onTap: onBack,
                filled: true,
              ),
            ),
          if (showBrand)
            const Padding(
              padding: EdgeInsetsDirectional.only(end: 12),
              child: BrandLockup(markSize: 34, fontSize: 16, letterSpacing: 2.2),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (eyebrow != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(eyebrow!.toUpperCase(), style: NovaTextStyles.caption(p.primaryBright)),
                  ),
                if (title != null)
                  Text(
                    title!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NovaTextStyles.heading(20, p.text),
                  ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: NovaTextStyles.small(p.textMuted),
                    ),
                  ),
              ],
            ),
          ),
          if (actions.isNotEmpty)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (int i = 0; i < actions.length; i++) ...<Widget>[
                  if (i > 0) const SizedBox(width: 8),
                  actions[i],
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class NovaBottomBar extends StatelessWidget {
  const NovaBottomBar({
    super.key,
    required this.index,
    required this.onChanged,
    required this.items,
    this.onAdd,
  });

  final int index;
  final ValueChanged<int> onChanged;
  final List<NovaNavItem> items;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    final double bottomInset = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 0, 14, (bottomInset > 0 ? bottomInset * 0.4 : 0) + 10),
      child: ClipRRect(
        borderRadius: NovaRadii.rXl,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            height: 68,
            decoration: BoxDecoration(
              color: p.isDark ? p.surface.withValues(alpha: 0.82) : Colors.white.withValues(alpha: 0.92),
              borderRadius: NovaRadii.rXl,
              border: Border.all(color: p.isDark ? p.stroke : p.strokeStrong.withValues(alpha: 0.2)),
              boxShadow: NovaShadows.lifted(p),
            ),
            child: Row(
              children: <Widget>[
                for (int i = 0; i < items.length; i++)
                  Expanded(
                    child: _NavButton(
                      item: items[i],
                      selected: index == i,
                      onTap: () => onChanged(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class NovaNavItem {
  const NovaNavItem({required this.label, required this.icon, this.activeIcon});

  final String label;
  final IconData icon;
  final IconData? activeIcon;
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.item, required this.selected, required this.onTap});

  final NovaNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    final Color active = p.primaryBright;
    final Color inactive = p.textDim;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: NovaDurations.normal,
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? active.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: NovaRadii.md,
          border: selected ? Border.all(color: active.withValues(alpha: 0.22)) : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              selected ? (item.activeIcon ?? item.icon) : item.icon,
              size: 21,
              color: selected ? active : inactive,
            ),
            const SizedBox(height: 3),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: NovaTextStyles.small(selected ? active : inactive).copyWith(
                fontSize: 9.5,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NovaTabStrip extends StatelessWidget {
  const NovaTabStrip({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
    this.icons,
    this.padding = const EdgeInsets.symmetric(horizontal: NovaSpace.page),
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  final List<IconData>? icons;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: labels.length,
        separatorBuilder: (BuildContext context, int i) => const SizedBox(width: 8),
        itemBuilder: (BuildContext context, int i) {
          final bool selected = i == index;
          final Color fg = selected ? Colors.white : p.textMuted;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onChanged(i),
            child: AnimatedContainer(
              duration: NovaDurations.normal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: selected ? NovaGradients.primary : null,
                color: selected ? null : p.cardSoft,
                borderRadius: NovaRadii.rPill,
                border: Border.all(color: selected ? Colors.transparent : p.stroke),
                boxShadow: selected ? NovaShadows.glow(p.indigo, alpha: 0.32, blur: 18, y: 6) : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (icons != null && i < icons!.length) ...<Widget>[
                    Icon(icons![i], size: 15, color: fg),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    labels[i],
                    style: NovaTextStyles.smallStrong(fg).copyWith(
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Slim progress line used at the very top of a screen while data refreshes.
class NovaLoadingBar extends StatelessWidget {
  const NovaLoadingBar({super.key, required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return AnimatedSwitcher(
      duration: NovaDurations.fast,
      child: visible
          ? LinearProgressIndicator(
              key: const ValueKey<String>('loading'),
              minHeight: 2,
              backgroundColor: Colors.transparent,
              color: p.primaryBright,
            )
          : const SizedBox(key: ValueKey<String>('idle'), height: 2),
    );
  }
}

/// A left-aligned section label with a gradient accent bar.
class NovaEyebrow extends StatelessWidget {
  const NovaEyebrow({super.key, required this.text, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            gradient: NovaGradients.primary,
            borderRadius: NovaRadii.rPill,
          ),
        ),
        const SizedBox(width: 8),
        Text(text.toUpperCase(), style: NovaTextStyles.caption(p.primaryBright)),
        if (icon != null) ...<Widget>[
          const SizedBox(width: 6),
          Icon(icon, size: 12, color: p.primaryBright),
        ],
      ],
    );
  }
}
