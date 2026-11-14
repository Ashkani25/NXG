import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:nexora/core/assets/app_assets.dart';
import 'package:nexora/games/kit_v2/ui/kit_v2_widgets.dart';

/// Canvas-side helpers for the kit_v2 art pack: a decoded-sprite cache for
/// CustomPainters, seat-colour -> piece mapping, a tumbling kit die, a board
/// frame and a compact multi-seat HUD. Everything falls back to procedural
/// drawing when an image is missing, so painters must treat sprites as optional.

/// Process-wide cache of decoded kit sprites for painters.
class KitSprites {
  KitSprites._();

  static final Map<String, ui.Image> _cache = <String, ui.Image>{};
  static final Map<String, Future<ui.Image?>> _pending = <String, Future<ui.Image?>>{};

  /// The decoded image, or null while loading / when the asset is missing.
  static ui.Image? get(String asset) => _cache[asset];

  /// Decodes [asset] once (at [width] px wide) and caches it.
  static Future<ui.Image?> load(String asset, {int width = 160}) {
    final ui.Image? hit = _cache[asset];
    if (hit != null) return Future<ui.Image?>.value(hit);
    final Future<ui.Image?>? p = _pending[asset];
    if (p != null) return p;
    final Future<ui.Image?> f = _decode(asset, width).then((ui.Image? img) {
      _pending.remove(asset);
      if (img != null) _cache[asset] = img;
      return img;
    });
    _pending[asset] = f;
    return f;
  }

  /// Loads every asset; completes when all have finished (missing ones are skipped).
  static Future<void> preload(List<String> assets, {int width = 160}) async {
    await Future.wait<ui.Image?>(assets.map((String a) => load(a, width: width)));
  }

  static Future<ui.Image?> _decode(String asset, int width) async {
    try {
      final ByteData data = await rootBundle.load(asset);
      final Uint8List bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      final ui.Codec codec = await ui.instantiateImageCodec(bytes, targetWidth: width);
      final ui.FrameInfo frame = await codec.getNextFrame();
      return frame.image;
    } catch (_) {
      return null;
    }
  }
}

/// Draws [img] scaled to fit inside [dst] (keeps aspect ratio, centred).
void kitPaintSprite(Canvas canvas, ui.Image img, Rect dst, {double opacity = 1}) {
  final double iw = img.width.toDouble();
  final double ih = img.height.toDouble();
  if (iw <= 0 || ih <= 0) return;
  final double s = math.min(dst.width / iw, dst.height / ih);
  final Rect to = Rect.fromCenter(center: dst.center, width: iw * s, height: ih * s);
  final Paint p = Paint()
    ..filterQuality = FilterQuality.medium
    ..isAntiAlias = true;
  if (opacity < 1) p.color = Color.fromRGBO(255, 255, 255, opacity.clamp(0.0, 1.0));
  canvas.drawImageRect(img, Rect.fromLTWH(0, 0, iw, ih), to, p);
}

/// Seat piece art for the four NEXORA seat colours
/// (turquoise, violet, gold, pink) used by Ludo and Snakes & Ladders.
const List<String> kKitSeatPieces = <String>[
  AppAssets.kitV2PiecesCheckerCyan1,
  AppAssets.kitV2PiecesCoin3dViolet,
  AppAssets.kitV2ButtonsOrbGold,
  AppAssets.kitV2PiecesCheckerPink1,
];

/// The kit piece for a seat colour; picks the nearest of the four seat hues.
String kitPieceForColor(Color c) {
  final HSVColor h = HSVColor.fromColor(c);
  final double hue = h.hue;
  if (hue >= 150 && hue < 215) return kKitSeatPieces[0]; // turquoise / cyan
  if (hue >= 215 && hue < 290) return kKitSeatPieces[1]; // violet
  if (hue >= 20 && hue < 75) return kKitSeatPieces[2]; // gold
  return kKitSeatPieces[3]; // pink / magenta / red
}

/// Kit glass die that tumbles while [rolling] (t = 0..1). With no value yet
/// it shows the 3D violet die. Falls back to [fallback] if art is missing.
class KitRollingDie extends StatelessWidget {
  const KitRollingDie({
    super.key,
    required this.value,
    required this.size,
    this.rolling = false,
    this.t = 0,
    this.glow,
    this.slate = false,
    this.fallback,
  });

  final int? value;
  final double size;
  final bool rolling;
  final double t;

  /// Glow colour behind the die (null = none).
  final Color? glow;
  final bool slate;
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    final int face = rolling ? 1 + ((t * 23).floor() * 5 + 2) % 6 : (value ?? 6);
    final double angle = rolling ? math.sin(t * math.pi * 4) * 0.6 * (1 - t) + t * math.pi * 2 : 0;
    final double hop = rolling ? (math.sin(t * math.pi * 3)).abs() * size * 0.35 * (1 - t) : 0;
    final bool blank = value == null && !rolling;
    final Widget face0 = blank
        ? KitImage(
            AppAssets.kitV2DiceDice3dViolet,
            width: size,
            height: size,
            cacheWidth: 216,
            fallback: fallback,
          )
        : KitDieFace(value: face, size: size, slate: slate, fallback: fallback);
    final Color? g = glow;
    return SizedBox(
      width: size,
      height: size,
      child: Transform.translate(
        offset: Offset(0, -hop),
        child: Transform.rotate(
          angle: angle,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(size * 0.22),
              boxShadow: g == null
                  ? null
                  : <BoxShadow>[BoxShadow(color: g.withValues(alpha: 0.55), blurRadius: size * 0.3)],
            ),
            child: face0,
          ),
        ),
      ),
    );
  }
}

/// Crystal rim around a board, in the kit's cyan/violet style, with gem
/// accents top and bottom. The child keeps its exact size; the frame is
/// painted outside it in [rim] logical pixels.
class KitBoardFrame extends StatelessWidget {
  const KitBoardFrame({
    super.key,
    required this.child,
    this.rim = 7,
    this.radius = 18,
    this.glow = true,
    this.gems = true,
  });

  final Widget child;
  final double rim;
  final double radius;
  final bool glow;
  final bool gems;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.all(rim),
          child: child,
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: _KitRimPainter(rim: rim, radius: radius, glow: glow)),
          ),
        ),
        if (gems) ...<Widget>[
          Positioned(
            top: -rim * 1.6,
            child: IgnorePointer(
              child: KitImage(AppAssets.kitV2ButtonsGemViolet,
                  width: rim * 3.6, height: rim * 3.6, cacheWidth: 96),
            ),
          ),
          Positioned(
            bottom: -rim * 1.6,
            child: IgnorePointer(
              child: KitImage(AppAssets.kitV2ButtonsGemViolet,
                  width: rim * 3.6, height: rim * 3.6, cacheWidth: 96),
            ),
          ),
        ],
      ],
    );
  }
}

class _KitRimPainter extends CustomPainter {
  _KitRimPainter({required this.rim, required this.radius, required this.glow});

  final double rim;
  final double radius;
  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect r = (Offset.zero & size).deflate(rim / 2);
    final RRect rr = RRect.fromRectAndRadius(r, Radius.circular(radius));
    if (glow) {
      canvas.drawRRect(
          rr,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = rim * 1.6
            ..color = const Color(0xFF8A3CFF).withValues(alpha: 0.45)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, rim * 1.4));
    }
    // Dark metal body of the rim.
    canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = rim
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[Color(0xFF2A1F5E), Color(0xFF120C33), Color(0xFF2B1660)],
          ).createShader(Offset.zero & size));
    // Neon inner and outer lines (cyan -> violet -> pink like the kit).
    final Shader neon = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[Color(0xFF2EE6FF), Color(0xFF8A5CFF), Color(0xFFFF4FD8), Color(0xFF2EE6FF)],
      stops: <double>[0, 0.4, 0.75, 1],
    ).createShader(Offset.zero & size);
    canvas.drawRRect(
        rr.deflate(rim / 2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..shader = neon);
    canvas.drawRRect(
        rr.inflate(rim / 2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..shader = neon);
    // Corner studs.
    final double d = rim * 0.55;
    for (final Offset c in <Offset>[r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]) {
      final Offset k = Offset(
        c.dx + (c.dx < size.width / 2 ? radius * 0.3 : -radius * 0.3),
        c.dy + (c.dy < size.height / 2 ? radius * 0.3 : -radius * 0.3),
      );
      final Path diamond = Path()
        ..moveTo(k.dx, k.dy - d)
        ..lineTo(k.dx + d, k.dy)
        ..lineTo(k.dx, k.dy + d)
        ..lineTo(k.dx - d, k.dy)
        ..close();
      canvas.drawPath(diamond, Paint()..color = const Color(0xFF7DF9FF));
    }
  }

  @override
  bool shouldRepaint(covariant _KitRimPainter oldDelegate) =>
      oldDelegate.rim != rim || oldDelegate.radius != radius || oldDelegate.glow != glow;
}

/// One seat for [KitSeatsHud].
class KitSeat {
  const KitSeat({
    required this.name,
    required this.subtitle,
    required this.color,
    required this.active,
    this.piece,
  });

  final String name;
  final String subtitle;
  final Color color;
  final bool active;

  /// Optional piece art shown inside the avatar ring.
  final String? piece;
}

/// Seats laid out two per row as compact kit player cards.
class KitSeatsHud extends StatelessWidget {
  const KitSeatsHud({super.key, required this.seats, this.reducedMotion = false});

  final List<KitSeat> seats;
  final bool reducedMotion;

  Widget _card(KitSeat s, int i) {
    final String? piece = s.piece;
    return KitPlayerHud(
      name: s.name,
      subtitle: s.subtitle,
      active: s.active,
      accent: s.color,
      violet: i.isOdd,
      compact: true,
      reducedMotion: reducedMotion,
      leading: piece == null
          ? null
          : Padding(
              padding: const EdgeInsets.all(1),
              child: KitImage(piece, cacheWidth: 96),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> rows = <Widget>[];
    for (int i = 0; i < seats.length; i += 2) {
      final List<Widget> kids = <Widget>[Expanded(child: _card(seats[i], i))];
      if (i + 1 < seats.length) {
        kids.add(const SizedBox(width: 6));
        kids.add(Expanded(child: _card(seats[i + 1], i + 1)));
      }
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 5));
      rows.add(Row(children: kids));
    }
    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }
}

/// A glass panel on the kit panel art (stretched), with a translucent
/// fallback. Use for question/info boxes; content sits inside [padding].
class KitGlassPanel extends StatelessWidget {
  const KitGlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(20, 16, 20, 16),
    this.violet = false,
  });

  final Widget child;
  final EdgeInsets padding;
  final bool violet;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: KitImage(
            violet ? AppAssets.kitV2PanelsPanelSmallA : AppAssets.kitV2PanelsPanelGlass,
            fit: BoxFit.fill,
            cacheWidth: 512,
            fallback: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: const Color(0xCC120D33),
                border: Border.all(color: const Color(0x887B5CFF)),
              ),
            ),
          ),
        ),
        Padding(padding: padding, child: child),
      ],
    );
  }
}

/// The kit card back (portrait or landscape), procedural fallback.
class KitCardBack extends StatelessWidget {
  const KitCardBack({super.key, required this.width, required this.height, this.landscape = false});

  final double width;
  final double height;
  final bool landscape;

  @override
  Widget build(BuildContext context) {
    return KitImage(
      landscape ? AppAssets.kitV2CardsCardBackLand : AppAssets.kitV2CardsCardBack,
      width: width,
      height: height,
      fit: BoxFit.fill,
      cacheWidth: 256,
      fallback: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(width * 0.12),
          gradient: const LinearGradient(colors: <Color>[Color(0xFF1B1660), Color(0xFF0A0B22)]),
          border: Border.all(color: const Color(0xFF2EE6D6), width: 1.5),
        ),
      ),
    );
  }
}
