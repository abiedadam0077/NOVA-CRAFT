import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models.dart';
import '../../core/strings.dart';
import '../theme.dart';
import '../tokens.dart';
import 'buttons.dart';
import 'feedback.dart';

class ServerAvatar extends StatelessWidget {
  const ServerAvatar({
    super.key,
    required this.name,
    this.size = 52,
    this.edition = 'JAVA',
    this.software = 'VANILLA',
    this.online = false,
    this.radius = NovaRadii.md,
    this.imageBytes,
  });

  final String name;
  final double size;
  final String edition;
  final String software;
  final bool online;
  final double radius;
  final Uint8List? imageBytes;

  List<Color> _colors(NovaPalette p) {
    switch (software.toUpperCase()) {
      case 'PAPER':
        return const <Color>[Color(0xFF3B82F6), Color(0xFF22D3EE)];
      case 'PURPUR':
        return const <Color>[Color(0xFFA855F7), Color(0xFF7C4DFF)];
      case 'FABRIC':
        return const <Color>[Color(0xFF22D3EE), Color(0xFF3B82F6)];
      case 'FORGE':
        return const <Color>[Color(0xFFF59E0B), Color(0xFFEF4444)];
      case 'NEOFORGE':
        return const <Color>[Color(0xFFFB923C), Color(0xFFF59E0B)];
      case 'BDS':
        return const <Color>[Color(0xFF22C55E), Color(0xFF059669)];
      default:
        return const <Color>[Color(0xFF4F5BFF), Color(0xFF7C4DFF)];
    }
  }

  String get _initials {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) return 'NC';
    final List<String> parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return trimmed.length == 1 ? trimmed.toUpperCase() : trimmed.substring(0, 2).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    final List<Color> colors = _colors(p);
    final BorderRadius br = BorderRadius.circular(radius);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius: br,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: colors,
              ),
              boxShadow: NovaShadows.glow(colors.first, alpha: p.isDark ? 0.35 : 0.2, blur: 18, y: 6),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                // Faint isometric grid to make the tile feel like a 3D block.
                CustomPaint(painter: _TilePainter()),
                if (imageBytes != null)
                  Image.memory(imageBytes!, fit: BoxFit.cover)
                else
                  Center(
                    child: Text(
                      _initials,
                      style: NovaTextStyles.display(size * 0.4, Colors.white).copyWith(
                        shadows: <Shadow>[Shadow(color: Colors.black.withValues(alpha: 0.28), blurRadius: 8)],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: size * 0.34,
              height: size * 0.34,
              decoration: BoxDecoration(
                color: p.cardHigh,
                shape: BoxShape.circle,
                border: Border.all(color: p.surface, width: 2),
              ),
              child: Icon(
                edition == 'BEDROCK' ? Icons.phone_android_rounded : Icons.desktop_windows_rounded,
                size: size * 0.17,
                color: edition == 'BEDROCK' ? p.successBright : p.primaryBright,
              ),
            ),
          ),
          if (online)
            Positioned(
              left: -1,
              top: -1,
              child: Container(
                width: size * 0.2,
                height: size * 0.2,
                decoration: BoxDecoration(
                  color: p.success,
                  shape: BoxShape.circle,
                  border: Border.all(color: p.surface, width: 2),
                  boxShadow: NovaShadows.glow(p.success, alpha: 0.6, blur: 10),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TilePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    const double step = 12;
    for (double x = -size.height; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), paint);
    }
    canvas.drawCircle(
      Offset(size.width * 0.82, size.height * 0.18),
      size.width * 0.22,
      Paint()..color = Colors.white.withValues(alpha: 0.10),
    );
  }

  @override
  bool shouldRepaint(_TilePainter oldDelegate) => false;
}

class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    this.value,
    this.unit,
    this.icon,
    this.accent,
    this.progress,
    this.unavailableHint,
  });

  final String label;
  final String? value;
  final String? unit;
  final IconData? icon;
  final Color? accent;
  final double? progress;
  final String? unavailableHint;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    final Color c = accent ?? p.primaryBright;
    final bool available = value != null;
    return Tooltip(
      message: available ? '' : (unavailableHint ?? L10n.t('statUnavailable')),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: p.isDark ? p.cardSoft.withValues(alpha: 0.92) : Colors.white,
          borderRadius: NovaRadii.md,
          border: Border.all(color: p.stroke),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: c.withValues(alpha: 0.14),
                    borderRadius: NovaRadii.rXs,
                  ),
                  child: Icon(icon ?? Icons.bolt_rounded, size: 14, color: c),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NovaTextStyles.caption(p.textDim).copyWith(letterSpacing: 0.4),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Flexible(
                  child: Text(
                    available ? value! : '—',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NovaTextStyles.number(21, available ? p.text : p.textDim),
                  ),
                ),
                if (available && unit != null && unit!.isNotEmpty) ...<Widget>[
                  const SizedBox(width: 3),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(unit!, style: NovaTextStyles.caption(p.textDim).copyWith(letterSpacing: 0.2)),
                  ),
                ],
              ],
            ),
            if (progress != null) ...<Widget>[
              const SizedBox(height: 8),
              ProgressTrack(value: progress!, color: c),
            ],
          ],
        ),
      ),
    );
  }
}

class ProgressTrack extends StatelessWidget {
  const ProgressTrack({
    super.key,
    required this.value,
    this.color,
    this.height = 5,
    this.background,
  });

  final double value;
  final Color? color;
  final double height;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    final Color c = color ?? p.primaryBright;
    return ClipRRect(
      borderRadius: NovaRadii.rPill,
      child: SizedBox(
        height: height,
        child: Stack(
          children: <Widget>[
            Container(color: background ?? c.withValues(alpha: 0.14)),
            FractionallySizedBox(
              widthFactor: value.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: <Color>[c.withValues(alpha: 0.75), c]),
                  borderRadius: NovaRadii.rPill,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AddressPill extends StatelessWidget {
  const AddressPill({
    super.key,
    required this.address,
    this.label,
    this.onCopy,
    this.compact = false,
    this.trailing,
  });

  final String address;
  final String? label;
  final VoidCallback? onCopy;
  final bool compact;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    final bool hasAddress = address.trim().isNotEmpty;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: compact ? 8 : 10),
      decoration: BoxDecoration(
        color: p.isDark ? p.bgDeep.withValues(alpha: 0.7) : p.cardHigh,
        borderRadius: NovaRadii.rMd,
        border: Border.all(color: hasAddress ? p.primary.withValues(alpha: 0.28) : p.stroke),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.dns_rounded, size: 16, color: hasAddress ? p.primaryBright : p.textDim),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (label != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 1),
                    child: Text(
                      label!,
                      style: NovaTextStyles.caption(p.textDim).copyWith(fontSize: 9),
                    ),
                  ),
                Text(
                  hasAddress ? address : L10n.t('noAddressYet'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: hasAddress
                      ? NovaTextStyles.monoStrong(compact ? 12 : 13.5, p.text)
                      : NovaTextStyles.small(p.textDim),
                ),
              ],
            ),
          ),
          if (trailing != null)
            trailing!
          else if (hasAddress && onCopy != null)
            NovaIconButton(
              icon: Icons.content_copy_rounded,
              size: 34,
              iconSize: 16,
              onTap: () {
                Clipboard.setData(ClipboardData(text: address));
                HapticFeedback.selectionClick();
                onCopy!();
              },
            ),
        ],
      ),
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.valueColor,
    this.monospace = false,
    this.onTap,
    this.trailing,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color? valueColor;
  final bool monospace;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    final Widget content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 16, color: p.textDim),
            const SizedBox(width: 9),
          ],
          Expanded(
            flex: 3,
            child: Text(label, style: NovaTextStyles.small(p.textMuted)),
          ),
          Expanded(
            flex: 4,
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: monospace
                  ? NovaTextStyles.monoStrong(12, valueColor ?? p.text)
                  : NovaTextStyles.smallStrong(valueColor ?? p.text),
            ),
          ),
          if (trailing != null) ...<Widget>[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
    if (onTap == null) return content;
    return InkWell(onTap: onTap, borderRadius: NovaRadii.rSm, child: content);
  }
}

class SoftChip extends StatelessWidget {
  const SoftChip({super.key, required this.label, this.color, this.icon});

  final String label;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    final Color c = color ?? p.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: NovaRadii.rXs,
        border: Border.all(color: c.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 11, color: c),
            const SizedBox(width: 4),
          ],
          Text(label, style: NovaTextStyles.caption(c).copyWith(letterSpacing: 0.3)),
        ],
      ),
    );
  }
}

class MetricBar extends StatelessWidget {
  const MetricBar({
    super.key,
    required this.label,
    required this.value,
    this.max = 1.0,
    this.display,
    this.color,
    this.icon,
  });

  final String label;
  final double? value;
  final double max;
  final String? display;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    final Color c = color ?? p.primaryBright;
    final bool available = value != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: 13, color: p.textDim),
              const SizedBox(width: 5),
            ],
            Expanded(child: Text(label, style: NovaTextStyles.caption(p.textDim).copyWith(letterSpacing: 0.3))),
            Text(
              display ?? (available ? '${(value! * 100).round()}%' : '—'),
              style: NovaTextStyles.smallStrong(available ? p.text : p.textDim),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ProgressTrack(value: available ? (value! / max).clamp(0.0, 1.0) : 0, color: c, height: 6),
      ],
    );
  }
}

class HeroTitle extends StatelessWidget {
  const HeroTitle({super.key, required this.server, this.online = false, this.trailing});

  final ServerConfig server;
  final bool online;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return Row(
      children: <Widget>[
        ServerAvatar(name: server.name, edition: server.edition, software: server.software, online: online, size: 54),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                server.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: NovaTextStyles.heading(20, p.text),
              ),
              const SizedBox(height: 3),
              Text(
                '${server.edition} ${server.mcVersion} · ${server.software}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: NovaTextStyles.small(p.textMuted),
              ),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class ServerCard extends StatelessWidget {
  const ServerCard({
    super.key,
    required this.server,
    required this.phase,
    this.playersOnline,
    this.playersMax,
    this.onTap,
    this.onMenu,
    this.selected = false,
  });

  final ServerConfig server;
  final ServerPhase phase;
  final int? playersOnline;
  final int? playersMax;
  final VoidCallback? onTap;
  final VoidCallback? onMenu;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    final bool online = phase == ServerPhase.online;
    final int? max = playersMax ?? server.maxPlayers;
    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: NovaGradients.card(p),
          borderRadius: NovaRadii.rLg,
          border: Border.all(
            color: selected
                ? p.primary.withValues(alpha: 0.5)
                : online
                    ? p.success.withValues(alpha: 0.22)
                    : p.stroke,
          ),
          boxShadow: NovaShadows.soft(p),
        ),
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                ServerAvatar(
                  name: server.name,
                  size: 46,
                  edition: server.edition,
                  software: server.software,
                  online: online,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        server.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: NovaTextStyles.bodyStrong(p.text).copyWith(fontSize: 15.5),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${server.edition == 'JAVA' ? 'Java' : 'Bedrock'} ${server.mcVersion} · ${_titleCase(server.software)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: NovaTextStyles.small(p.textMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                StatusPill(phase: phase, dense: true),
                if (onMenu != null)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 2),
                    child: NovaIconButton(
                      icon: Icons.more_vert_rounded,
                      size: 32,
                      iconSize: 17,
                      onTap: onMenu,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Icon(Icons.groups_rounded, size: 14, color: p.textDim),
                const SizedBox(width: 5),
                Text(
                  playersOnline != null ? '$playersOnline / $max' : '— / $max',
                  style: NovaTextStyles.smallStrong(playersOnline != null ? p.text : p.textDim),
                ),
                const SizedBox(width: 14),
                Icon(Icons.folder_rounded, size: 13, color: p.textDim),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    server.repoFull,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NovaTextStyles.small(p.textDim),
                  ),
                ),
                if (server.repoPrivate)
                  Icon(Icons.lock_rounded, size: 12, color: p.textDim)
                else
                  Icon(Icons.public_rounded, size: 12, color: p.textDim),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _titleCase(String value) {
  if (value.isEmpty) return value;
  return value.substring(0, 1).toUpperCase() + value.substring(1).toLowerCase();
}

class ArtTile extends StatelessWidget {
  const ArtTile({
    super.key,
    required this.asset,
    required this.title,
    required this.body,
    this.onTap,
    this.height = 150,
    this.tag,
  });

  final String asset;
  final String title;
  final String body;
  final VoidCallback? onTap;
  final double height;
  final Widget? tag;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return PressableScale(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: NovaRadii.rLg,
        child: SizedBox(
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Image.asset(asset, fit: BoxFit.cover),
              const DecoratedBox(decoration: BoxDecoration(gradient: NovaGradients.heroScrim)),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    if (tag != null) ...<Widget>[tag!, const SizedBox(height: 8)],
                    Text(title, style: NovaTextStyles.heading(17, Colors.white)),
                    const SizedBox(height: 3),
                    Text(body, style: NovaTextStyles.small(p.textMuted)),
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

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.icon,
    this.actionLabel,
    this.onAction,
    this.padding = const EdgeInsets.all(16),
  });

  final String title;
  final Widget child;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: NovaGradients.card(p),
        borderRadius: NovaRadii.rLg,
        border: Border.all(color: p.stroke),
        boxShadow: NovaShadows.soft(p),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: 16, color: p.primaryBright),
                const SizedBox(width: 7),
              ],
              Expanded(child: Text(title, style: NovaTextStyles.title(p.text))),
              if (actionLabel != null && onAction != null)
                GestureDetector(
                  onTap: onAction,
                  behavior: HitTestBehavior.opaque,
                  child: Text(actionLabel!, style: NovaTextStyles.smallStrong(p.primaryBright)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class AvatarBadge extends StatelessWidget {
  const AvatarBadge({super.key, required this.name, this.size = 44, this.imageUrl, this.accent});

  final String name;
  final double size;
  final String? imageUrl;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    final Color c = accent ?? p.violet;
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: p.strokeStrong.withValues(alpha: 0.4), width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.network(
          imageUrl!,
          fit: BoxFit.cover,
          errorBuilder: (BuildContext context, Object error, StackTrace? stack) => _fallback(p, c),
        ),
      );
    }
    return _fallback(p, c);
  }

  Widget _fallback(NovaPalette p, Color c) {
    final String initials = name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: <Color>[c, p.indigo]),
      ),
      alignment: Alignment.center,
      child: Text(initials, style: NovaTextStyles.heading(size * 0.4, Colors.white)),
    );
  }
}

class BrandDivider extends StatelessWidget {
  const BrandDivider({super.key, this.label, this.padding = const EdgeInsets.symmetric(vertical: 14)});

  final String? label;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    if (label == null) {
      return Padding(
        padding: padding,
        child: Container(
          height: 1,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: <Color>[Colors.transparent, p.stroke, Colors.transparent],
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: padding,
      child: Row(
        children: <Widget>[
          Expanded(child: Container(height: 1, color: p.stroke)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(label!.toUpperCase(), style: NovaTextStyles.caption(p.textDim)),
          ),
          Expanded(child: Container(height: 1, color: p.stroke)),
        ],
      ),
    );
  }
}
