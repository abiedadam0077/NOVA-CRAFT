import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// The signature NOVA CRAFT backdrop: deep navy, a faint voxel grid, and
/// electric blue / violet light bleeding in from the edges.
class AuroraBackground extends StatelessWidget {
  const AuroraBackground({
    super.key,
    required this.child,
    this.intensity = 1.0,
    this.showGrid = true,
    this.glowTop = true,
  });

  final Widget child;
  final double intensity;
  final bool showGrid;
  final bool glowTop;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[p.bg, p.bg, p.bgDeep],
          stops: const <double>[0.0, 0.55, 1.0],
        ),
      ),
      child: Stack(
        children: <Widget>[
          if (p.isDark) ...<Widget>[
            Positioned(
              top: -180,
              right: -120,
              child: GlowOrb(
                size: 420,
                color: p.primary.withValues(alpha: 0.22 * intensity),
              ),
            ),
            Positioned(
              top: 120,
              left: -200,
              child: GlowOrb(
                size: 460,
                color: p.violet.withValues(alpha: 0.14 * intensity),
              ),
            ),
            Positioned(
              bottom: -220,
              right: -60,
              child: GlowOrb(
                size: 520,
                color: p.indigo.withValues(alpha: 0.12 * intensity),
              ),
            ),
          ] else ...<Widget>[
            Positioned(
              top: -160,
              right: -140,
              child: GlowOrb(size: 380, color: p.primary.withValues(alpha: 0.10 * intensity)),
            ),
            Positioned(
              bottom: -200,
              left: -160,
              child: GlowOrb(size: 420, color: p.violet.withValues(alpha: 0.08 * intensity)),
            ),
          ],
          if (showGrid)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _GridPainter(
                    color: p.isDark ? Colors.white : p.primary,
                    opacity: p.isDark ? 0.022 : 0.05,
                  ),
                ),
              ),
            ),
          if (glowTop)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 220,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        p.primary.withValues(alpha: p.isDark ? 0.08 : 0.05),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

class GlowOrb extends StatelessWidget {
  const GlowOrb({super.key, required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: <Color>[color, color.withValues(alpha: 0.0)],
            stops: const <double>[0.0, 1.0],
          ),
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter({required this.color, required this.opacity});

  final Color color;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color.withValues(alpha: opacity)
      ..strokeWidth = 1;
    const double step = 44;
    final double skew = size.height * 0.16;

    // Vertical lines with a slight downward skew: a stylised voxel grid.
    for (double x = -step; x < size.width + step; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x + skew, size.height), paint);
    }
    // Horizontal perspective lines that get denser toward the top.
    double y = size.height;
    double gap = step;
    while (y > -step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      gap = math.max(18, gap * 0.92);
      y -= gap;
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) => oldDelegate.opacity != opacity || oldDelegate.color != color;
}

/// Adds a dark scrim + soft top glow behind content that sits on artwork.
class ArtScrim extends StatelessWidget {
  const ArtScrim({super.key, required this.child, this.topGlow = false});

  final Widget child;
  final bool topGlow;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: p.isDark
                  ? const <Color>[Color(0xE6070B18), Color(0xF2070B18)]
                  : const <Color>[Color(0xE6F2F5FC), Color(0xFFF2F5FC)],
            ),
          ),
        ),
        if (topGlow)
          Positioned(
            top: -60,
            left: -40,
            right: -40,
            height: 200,
            child: GlowOrb(size: 260, color: p.primary.withValues(alpha: 0.22)),
          ),
        child,
      ],
    );
  }
}

/// Small floating "dust" particles used on the splash/onboarding art.
class ParticleField extends StatefulWidget {
  const ParticleField({super.key, this.count = 26, this.color});

  final int count;
  final Color? color;

  @override
  State<ParticleField> createState() => _ParticleFieldState();
}

class _ParticleFieldState extends State<ParticleField> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(seconds: 14))..repeat();
  late final List<_Particle> _particles = _buildParticles(widget.count);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color color = widget.color ?? Colors.white;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? child) {
          return CustomPaint(
            painter: _ParticlePainter(particles: _particles, t: _controller.value, color: color),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _Particle {
  _Particle(this.x, this.y, this.radius, this.speed, this.phase);

  final double x;
  final double y;
  final double radius;
  final double speed;
  final double phase;
}

List<_Particle> _buildParticles(int count) {
  final math.Random random = math.Random(7);
  return List<_Particle>.generate(
    count,
    (int i) => _Particle(
      random.nextDouble(),
      random.nextDouble(),
      0.8 + random.nextDouble() * 2.2,
      0.2 + random.nextDouble() * 0.8,
      random.nextDouble() * math.pi * 2,
    ),
  );
}

class _ParticlePainter extends CustomPainter {
  _ParticlePainter({required this.particles, required this.t, required this.color});

  final List<_Particle> particles;
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint();
    for (final _Particle particle in particles) {
      final double drift = ((particle.y - t * particle.speed * 0.25) % 1.0 + 1.0) % 1.0;
      final double twinkle = 0.35 + 0.65 * (0.5 + 0.5 * math.sin(t * math.pi * 2 + particle.phase));
      paint.color = color.withValues(alpha: 0.45 * twinkle);
      canvas.drawCircle(
        Offset(particle.x * size.width, drift * size.height),
        particle.radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter oldDelegate) => oldDelegate.t != t;
}

/// Fades content out at the bottom so lists never collide with the nav bar.
class BottomFade extends StatelessWidget {
  const BottomFade({super.key, this.height = 96});

  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.nova;
    return IgnorePointer(
      child: Container(
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[p.bg.withValues(alpha: 0.0), p.bg.withValues(alpha: 0.92), p.bg],
          ),
        ),
      ),
    );
  }
}

class NovaIcons {
  const NovaIcons._();

  static const IconData home = Icons.space_dashboard_rounded;
  static const IconData servers = Icons.dns_rounded;
  static const IconData console = Icons.terminal_rounded;
  static const IconData files = Icons.folder_copy_rounded;
  static const IconData settings = Icons.settings_rounded;
  static const IconData mods = Icons.extension_rounded;
  static const IconData backups = Icons.backup_rounded;
  static const IconData worlds = Icons.public_rounded;
  static const IconData network = Icons.hub_rounded;
  static const IconData players = Icons.groups_rounded;
  static const IconData runs = Icons.history_rounded;
  static const IconData security = Icons.shield_rounded;
  static const IconData spark = Icons.auto_awesome_rounded;
  static const IconData cube = Icons.view_in_ar_rounded;
  static const IconData bolt = Icons.bolt_rounded;
  static const IconData copy = Icons.content_copy_rounded;
  static const IconData play = Icons.play_arrow_rounded;
  static const IconData stop = Icons.stop_rounded;
  static const IconData restart = Icons.refresh_rounded;
  static const IconData power = Icons.power_settings_new_rounded;
  static const IconData chevron = Icons.chevron_right_rounded;
  static const IconData chevronBack = Icons.arrow_back_ios_new_rounded;
  static const IconData arrowBack = Icons.arrow_back_rounded;
  static const IconData close = Icons.close_rounded;
  static const IconData search = Icons.search_rounded;
  static const IconData filter = Icons.tune_rounded;
  static const IconData upload = Icons.upload_rounded;
  static const IconData download = Icons.download_rounded;
  static const IconData delete = Icons.delete_outline_rounded;
  static const IconData edit = Icons.edit_rounded;
  static const IconData more = Icons.more_horiz_rounded;
  static const IconData moreVertical = Icons.more_vert_rounded;
  static const IconData add = Icons.add_rounded;
  static const IconData check = Icons.check_rounded;
  static const IconData error = Icons.error_outline_rounded;
  static const IconData warning = Icons.warning_amber_rounded;
  static const IconData info = Icons.info_outline_rounded;
  static const IconData link = Icons.link_rounded;
  static const IconData external = Icons.open_in_new_rounded;
  static const IconData github = Icons.code_rounded;
  static const IconData terminal = Icons.terminal_rounded;
  static const IconData memory = Icons.memory_rounded;
  static const IconData speed = Icons.speed_rounded;
  static const IconData clock = Icons.schedule_rounded;
  static const IconData calendar = Icons.calendar_today_rounded;
  static const IconData folder = Icons.folder_rounded;
  static const IconData file = Icons.insert_drive_file_rounded;
  static const IconData image = Icons.image_rounded;
  static const IconData zip = Icons.folder_zip_rounded;
  static const IconData code = Icons.code_rounded;
  static const IconData send = Icons.send_rounded;
  static const IconData clear = Icons.layers_clear_rounded;
  static const IconData jump = Icons.vertical_align_bottom_rounded;
  static const IconData refresh = Icons.refresh_rounded;
  static const IconData globe = Icons.language_rounded;
  static const IconData moon = Icons.dark_mode_rounded;
  static const IconData sun = Icons.light_mode_rounded;
  static const IconData phone = Icons.smartphone_rounded;
  static const IconData logout = Icons.logout_rounded;
  static const IconData lock = Icons.lock_rounded;
  static const IconData key = Icons.vpn_key_rounded;
  static const IconData cloud = Icons.cloud_rounded;
  static const IconData trend = Icons.trending_up_rounded;
  static const IconData sort = Icons.sort_rounded;
  static const IconData pause = Icons.pause_rounded;
  static const IconData dot = Icons.circle;
  static const IconData menu = Icons.menu_rounded;
  static const IconData grid = Icons.grid_view_rounded;
  static const IconData list = Icons.view_list_rounded;
}
