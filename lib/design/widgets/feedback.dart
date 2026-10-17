import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/strings.dart';
import '../theme.dart';
import '../tokens.dart';
import 'buttons.dart';

enum PillTone { neutral, primary, success, warning, danger, violet }

class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.label,
    this.tone = PillTone.neutral,
    this.icon,
    this.pulse = false,
    this.dense = false,
    this.color,
  });

  final String label;
  final PillTone tone;
  final IconData? icon;
  final bool pulse;
  final bool dense;
  final Color? color;

  Color _resolve(NovaPalette p) {
    switch (tone) {
      case PillTone.primary:
        return p.primaryBright;
      case PillTone.success:
        return p.success;
      case PillTone.warning:
        return p.warning;
      case PillTone.danger:
        return p.danger;
      case PillTone.violet:
        return p.violet;
      case PillTone.neutral:
        return p.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    final Color c = color ?? _resolve(p);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10, vertical: dense ? 4 : 6),
      decoration: BoxDecoration(
        color: c.withValues(alpha: p.isDark ? 0.14 : 0.10),
        borderRadius: NovaRadii.rPill,
        border: Border.all(color: c.withValues(alpha: 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (pulse)
            _PulsingDot(color: c, size: dense ? 6 : 7)
          else if (icon != null)
            Icon(icon, size: dense ? 11 : 13, color: c)
          else
            Container(
              width: dense ? 6 : 7,
              height: dense ? 6 : 7,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle),
            ),
          SizedBox(width: dense ? 5 : 6),
          Text(
            label,
            style: NovaTextStyles.smallStrong(c).copyWith(fontSize: dense ? 10.5 : 11.5),
          ),
        ],
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        final double t = _controller.value;
        final double halo = widget.size * (1.0 + t * 1.9);
        return SizedBox(
          width: widget.size * 2.6,
          height: widget.size * 2.6,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Container(
                width: halo,
                height: halo,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(alpha: 0.30 * (1 - t)),
                ),
              ),
              Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
              ),
            ],
          ),
        );
      },
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.phase, this.dense = false});

  final ServerPhase phase;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    switch (phase) {
      case ServerPhase.online:
        return Pill(label: L10n.t('online'), tone: PillTone.success, pulse: true, dense: dense);
      case ServerPhase.offline:
        return Pill(label: L10n.t('offline'), tone: PillTone.neutral, dense: dense);
      case ServerPhase.starting:
        return Pill(label: L10n.t('starting'), tone: PillTone.warning, pulse: true, dense: dense);
      case ServerPhase.stopping:
        return Pill(label: L10n.t('stopping'), tone: PillTone.warning, pulse: true, dense: dense);
      case ServerPhase.error:
        return Pill(label: L10n.t('error'), tone: PillTone.danger, dense: dense);
      case ServerPhase.unknown:
        return Pill(label: L10n.t('unknown'), tone: PillTone.neutral, dense: dense);
    }
  }
}

class NovaLoader extends StatefulWidget {
  const NovaLoader({super.key, this.size = 28, this.stroke = 2.6});

  final double size;
  final double stroke;

  @override
  State<NovaLoader> createState() => _NovaLoaderState();
}

class _NovaLoaderState extends State<NovaLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: RotationTransition(
        turns: _controller,
        child: CustomPaint(
          painter: _RingPainter(stroke: widget.stroke, start: p.primaryBright, end: p.violet),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.stroke, required this.start, required this.end});

  final double stroke;
  final Color start;
  final Color end;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final Paint track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = start.withValues(alpha: 0.14);
    canvas.drawArc(rect.deflate(stroke / 2), 0, 6.28318, false, track);
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(colors: <Color>[start.withValues(alpha: 0.0), start, end]).createShader(rect);
    canvas.drawArc(rect.deflate(stroke / 2), -0.4, 4.2, false, paint);
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) => false;
}

class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.height = 14, this.width, this.radius = 8});

  final double height;
  final double? width;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

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
        return Container(
          height: widget.height,
          width: widget.width,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              colors: <Color>[
                p.cardSoft,
                Color.alphaBlend(p.primary.withValues(alpha: 0.10 + 0.08 * _controller.value), p.cardSoft),
                p.cardSoft,
              ],
            ),
          ),
        );
      },
    );
  }
}

class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 4, this.cardHeight = 108});

  final int count;
  final double cardHeight;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return Column(
      children: List<Widget>.generate(count, (int i) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          height: cardHeight,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: p.cardSoft,
            borderRadius: NovaRadii.rLg,
            border: Border.all(color: p.stroke),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Skeleton(height: 42, width: 42, radius: 12),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const <Widget>[
                        Skeleton(height: 12, width: 140),
                        SizedBox(height: 8),
                        Skeleton(height: 10, width: 90),
                      ],
                    ),
                  ),
                ],
              ),
              const Spacer(),
              const Skeleton(height: 10, width: double.infinity),
            ],
          ),
        );
      }),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.body,
    this.icon = Icons.inbox_rounded,
    this.actionLabel,
    this.onAction,
    this.artAsset,
    this.compact = false,
  });

  final String title;
  final String? body;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? artAsset;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24, vertical: compact ? 24 : 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (artAsset != null)
              ClipRRect(
                borderRadius: NovaRadii.rXl,
                child: Image.asset(artAsset!, height: compact ? 120 : 176, fit: BoxFit.cover),
              )
            else
              Container(
                width: compact ? 56 : 72,
                height: compact ? 56 : 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: p.primary.withValues(alpha: 0.10),
                  border: Border.all(color: p.primary.withValues(alpha: 0.22)),
                  boxShadow: NovaShadows.glow(p.primary, alpha: p.isDark ? 0.18 : 0.1, blur: 26),
                ),
                child: Icon(icon, size: compact ? 24 : 30, color: p.primaryBright),
              ),
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center, style: NovaTextStyles.heading(compact ? 16 : 18, p.text)),
            if (body != null) ...<Widget>[
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Text(body!, textAlign: TextAlign.center, style: NovaTextStyles.small(p.textMuted)),
              ),
            ],
            if (actionLabel != null && onAction != null) ...<Widget>[
              const SizedBox(height: 20),
              NovaButton(
                label: actionLabel!,
                onPressed: onAction,
                expand: false,
                size: NovaButtonSize.compact,
                height: 48,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.message,
    this.title,
    this.onRetry,
    this.retryLabel,
    this.icon = Icons.error_outline_rounded,
    this.compact = false,
  });

  final String message;
  final String? title;
  final VoidCallback? onRetry;
  final String? retryLabel;
  final IconData icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24, vertical: compact ? 20 : 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: compact ? 48 : 62,
              height: compact ? 48 : 62,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: p.danger.withValues(alpha: 0.10),
                border: Border.all(color: p.danger.withValues(alpha: 0.28)),
              ),
              child: Icon(icon, size: compact ? 22 : 28, color: p.dangerSoft),
            ),
            const SizedBox(height: 14),
            Text(
              title ?? L10n.t('errorGeneric'),
              textAlign: TextAlign.center,
              style: NovaTextStyles.heading(compact ? 15 : 17, p.text),
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: Text(message, textAlign: TextAlign.center, style: NovaTextStyles.small(p.textMuted)),
            ),
            if (onRetry != null) ...<Widget>[
              const SizedBox(height: 18),
              NovaButton(
                label: retryLabel ?? L10n.t('retry'),
                icon: Icons.refresh_rounded,
                onPressed: onRetry,
                expand: false,
                size: NovaButtonSize.compact,
                height: 46,
                variant: NovaButtonVariant.secondary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class InlineError extends StatelessWidget {
  const InlineError({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.danger.withValues(alpha: 0.10),
        borderRadius: NovaRadii.rMd,
        border: Border.all(color: p.danger.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.error_outline_rounded, size: 18, color: p.dangerSoft),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: NovaTextStyles.small(p.text))),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: p.dangerSoft,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(L10n.t('retry'), style: NovaTextStyles.smallStrong(p.dangerSoft)),
            ),
        ],
      ),
    );
  }
}

enum ToastKind { info, success, error, warning }

void showNovaToast(BuildContext context, String message, {ToastKind kind = ToastKind.info}) {
  final p = context.nova;
  Color accent;
  IconData icon;
  switch (kind) {
    case ToastKind.success:
      accent = p.success;
      icon = Icons.check_circle_rounded;
      break;
    case ToastKind.error:
      accent = p.danger;
      icon = Icons.error_rounded;
      break;
    case ToastKind.warning:
      accent = p.warning;
      icon = Icons.warning_amber_rounded;
      break;
    case ToastKind.info:
      accent = p.primaryBright;
      icon = Icons.info_rounded;
      break;
  }
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.transparent,
      elevation: 0,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      duration: const Duration(seconds: 3),
      content: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: p.cardHigh,
          borderRadius: NovaRadii.rMd,
          border: Border.all(color: accent.withValues(alpha: 0.4)),
          boxShadow: NovaShadows.lifted(p),
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 19, color: accent),
            const SizedBox(width: 10),
            Expanded(child: Text(message, style: NovaTextStyles.small(p.text))),
          ],
        ),
      ),
    ),
  );
}

Future<bool> showNovaConfirm(
  BuildContext context, {
  required String title,
  required String body,
  String? confirmLabel,
  String? cancelLabel,
  bool danger = false,
  IconData? icon,
}) async {
  final p = context.nova;
  final bool? result = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (BuildContext ctx) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: NovaRadii.rXl,
            border: Border.all(color: p.stroke),
            boxShadow: NovaShadows.lifted(p),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: (danger ? p.danger : p.primary).withValues(alpha: 0.14),
                      border: Border.all(color: (danger ? p.danger : p.primary).withValues(alpha: 0.3)),
                    ),
                    child: Icon(
                      icon ?? (danger ? Icons.warning_amber_rounded : Icons.help_outline_rounded),
                      color: danger ? p.dangerSoft : p.primaryBright,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(title, style: NovaTextStyles.heading(18, p.text))),
                ],
              ),
              const SizedBox(height: 14),
              Text(body, style: NovaTextStyles.body(p.textMuted)),
              const SizedBox(height: 22),
              Row(
                children: <Widget>[
                  Expanded(
                    child: NovaButton(
                      label: cancelLabel ?? L10n.t('cancel'),
                      variant: NovaButtonVariant.secondary,
                      height: 48,
                      onPressed: () => Navigator.of(ctx).pop(false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: NovaButton(
                      label: confirmLabel ?? L10n.t('confirm'),
                      variant: danger ? NovaButtonVariant.danger : NovaButtonVariant.primary,
                      height: 48,
                      onPressed: () => Navigator.of(ctx).pop(true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
  return result ?? false;
}

Future<void> showNovaSheet(
  BuildContext context, {
  required Widget child,
  bool dismissible = true,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: dismissible,
    enableDrag: dismissible,
    backgroundColor: Colors.transparent,
    builder: (BuildContext ctx) {
      final p = ctx.nova;
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: p.stroke),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const SizedBox(height: 10),
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: p.textDim.withValues(alpha: 0.5),
                    borderRadius: NovaRadii.rPill,
                  ),
                ),
                Flexible(child: child),
              ],
            ),
          ),
        ),
      );
    },
  );
}
