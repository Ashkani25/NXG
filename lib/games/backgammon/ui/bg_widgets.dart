import 'dart:math';

import 'package:flutter/material.dart';

import 'package:nexora/core/assets/app_assets.dart';
import 'package:nexora/games/kit_v2/ui/kit_v2_widgets.dart';
import 'bg_geometry.dart';

/// One textured checker (asset with procedural fallback).
class BgChecker extends StatelessWidget {
  const BgChecker({super.key, required this.player, this.size = BgGeom.d, this.kit = false});

  final int player;
  final double size;

  /// true = kit_v2 cyan/pink crystal checkers, false = classic art.
  final bool kit;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: <BoxShadow>[
          BoxShadow(color: Color(0x99000000), blurRadius: 8, offset: Offset(0, 4)),
        ],
      ),
      child: Image.asset(
        kit
            ? AppAssets.kitV2Checker(player == 0 ? 'cyan' : 'pink', 1)
            : (player == 0
                ? AppAssets.gamesBackgammonCheckerLight
                : AppAssets.gamesBackgammonCheckerDark),
        width: size,
        height: size,
        cacheWidth: 128,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        errorBuilder: (BuildContext c, Object e, StackTrace? s) =>
            CustomPaint(size: Size(size, size), painter: BgCheckerPainter(player, kit: kit)),
      ),
    );
  }
}

/// A die: tumbling kit faces while [rolling] (t = 0..1), then the kit face
/// for [value] (procedural face if the image fails).
class BgDie extends StatelessWidget {
  const BgDie({
    super.key,
    required this.value,
    required this.size,
    this.used = false,
    this.rolling = false,
    this.t = 0,
    this.variant = 0,
    this.kit = false,
  });

  final int value;
  final double size;
  final bool used;
  final bool rolling;
  final double t;
  final int variant;

  /// true = kit_v2 glass dice faces, false = classic art + procedural face.
  final bool kit;

  @override
  Widget build(BuildContext context) {
    if (rolling) {
      final double dir = variant.isEven ? 1 : -1;
      final double bounce = (sin(t * pi * 3)).abs() * size * 0.5 * (1 - t);
      final double drift = sin(t * pi * 2 + variant) * size * 0.25 * (1 - t);
      return Transform.translate(
        offset: Offset(drift, -bounce),
        child: Transform.rotate(
          angle: dir * t * pi * 5,
          child: Image.asset(
            kit
                ? AppAssets.kitV2DieBlue(1 + ((t * 17).floor() + variant) % 6)
                : (variant.isEven ? AppAssets.gamesBackgammonDieA : AppAssets.gamesBackgammonDieB),
            width: kit ? size : size * 1.1,
            height: kit ? size : size * 1.1,
            cacheWidth: kit ? 192 : 160,
            gaplessPlayback: true,
            fit: BoxFit.contain,
            errorBuilder: (BuildContext c, Object e, StackTrace? s) => CustomPaint(
              size: Size(size, size),
              painter: BgDieFacePainter(1 + ((t * 17).floor() + variant) % 6),
            ),
          ),
        ),
      );
    }
    return AnimatedScale(
      scale: used ? 0.82 : 1.0,
      duration: const Duration(milliseconds: 220),
      child: AnimatedOpacity(
        opacity: used ? 0.45 : 1.0,
        duration: const Duration(milliseconds: 220),
        child: kit
            ? KitDieFace(
                value: value,
                size: size,
                fallback: CustomPaint(
                  size: Size(size, size),
                  painter: BgDieFacePainter(value, used: used),
                ),
              )
            : CustomPaint(
                size: Size(size, size),
                painter: BgDieFacePainter(value, used: used),
              ),
      ),
    );
  }
}

/// Cosmic backdrop with a deterministic star field.
class BgSpaceBackground extends StatelessWidget {
  const BgSpaceBackground({super.key, required this.fancy});
  final bool fancy;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.2),
          radius: 1.3,
          colors: <Color>[Color(0xFF2A1F08), Color(0xFF0D0B12), Color(0xFF050818)],
          stops: <double>[0, 0.55, 1],
        ),
      ),
      child: CustomPaint(painter: _StarPainter(fancy ? 140 : 60)),
    );
  }
}

class _StarPainter extends CustomPainter {
  _StarPainter(this.count);
  final int count;

  @override
  void paint(Canvas canvas, Size size) {
    final Random r = Random(7);
    final Paint p = Paint();
    for (int i = 0; i < count; i++) {
      final double x = r.nextDouble() * size.width;
      final double y = r.nextDouble() * size.height;
      final double s = r.nextDouble() * 1.6 + 0.3;
      p.color = (i % 7 == 0 ? const Color(0xFFFFC857) : const Color(0xFFEAF6FF))
          .withValues(alpha: 0.25 + r.nextDouble() * 0.6);
      canvas.drawCircle(Offset(x, y), s, p);
    }
  }

  @override
  bool shouldRepaint(covariant _StarPainter oldDelegate) => oldDelegate.count != count;
}

/// Glassy pill button used by the HUD.
class BgButton extends StatelessWidget {
  const BgButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.color = const Color(0xFFFFC857),
    this.primary = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final Color color;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              gradient: primary
                  ? LinearGradient(colors: <Color>[color, color.withValues(alpha: 0.7)])
                  : null,
              color: primary ? null : const Color(0x22FFFFFF),
              border: Border.all(color: color.withValues(alpha: 0.8), width: 1.2),
              boxShadow: primary && enabled
                  ? <BoxShadow>[BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 16)]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, size: 18, color: primary ? const Color(0xFF1A1206) : color),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: primary ? const Color(0xFF1A1206) : const Color(0xFFEAF6FF),
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
