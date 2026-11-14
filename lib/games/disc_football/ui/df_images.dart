// Disc Football image loading + procedurally baked sprites (Godot match_view.gd _radial/_gloss_tex,
// the ball shader's lighting baked into two overlay sprites, the field shader's feathered edges).
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;

import 'package:nexora/core/assets/app_assets.dart';
import '../core/data.dart';

/// Asset path helpers for the football art.
class DfArt {
  DfArt._();
  static String team(String id) => AppAssets.dfTeam(teamKey(teamById(id)));
  static String ball(int i) => AppAssets.dfBall(i.clamp(0, kBallCount - 1).toInt());
  static String field(int i) => AppAssets.dfField(kFields[i.clamp(0, kFields.length - 1).toInt()].id);
  static String fieldThumb(int i) => AppAssets.dfFieldThumb(kFields[i.clamp(0, kFields.length - 1).toInt()].id);
  static String goal(String gs) => AppAssets.dfGoal(gs);
  static String bannerGoal() => AppAssets.dfUi('banner_goal');
}

final Map<String, Future<ui.Image?>> _cache = <String, Future<ui.Image?>>{};

/// Decode an asset image (optionally downscaled to [width]). Small images are cached for the app
/// lifetime ([cache] true); big ones (fields) are owned by the caller. Never throws: null on failure.
Future<ui.Image?> dfLoadImage(String asset, {int? width, bool cache = true}) {
  final String key = '$asset@${width ?? 0}';
  if (cache) {
    final Future<ui.Image?>? hit = _cache[key];
    if (hit != null) return hit;
  }
  final Future<ui.Image?> f = _decode(asset, width);
  if (cache) _cache[key] = f;
  return f;
}

Future<ui.Image?> _decode(String asset, int? width) async {
  try {
    final ByteData data = await rootBundle.load(asset);
    final ui.Codec codec = await ui.instantiateImageCodec(data.buffer.asUint8List(), targetWidth: width);
    final ui.FrameInfo fi = await codec.getNextFrame();
    return fi.image;
  } catch (_) {
    return null;
  }
}

/// Generated sprites shared by every match view.
class DfSprites {
  DfSprites._(this.shadow, this.dot, this.gloss, this.ballMul, this.ballAdd);
  final ui.Image shadow;
  final ui.Image dot;
  final ui.Image gloss;

  /// Ball lighting: multiply sprite (diffuse x ambient occlusion x rim darkening) …
  final ui.Image ballMul;

  /// … and additive sprite (specular + hot spot + blue rim light).
  final ui.Image ballAdd;

  static Future<DfSprites?>? _f;
  static DfSprites? ready;

  static Future<DfSprites?> load() {
    _f ??= _build();
    return _f!;
  }

  static Future<DfSprites?> _build() async {
    try {
      final ui.Image shadow = await _radial(128, const <double>[0, 0.55, 1],
          const <ui.Color>[ui.Color(0xFF000000), ui.Color(0x80000000), ui.Color(0x00000000)]);
      final ui.Image dot = await _radial(64, const <double>[0, 0.35, 1],
          const <ui.Color>[ui.Color(0xFFFFFFFF), ui.Color(0x73FFFFFF), ui.Color(0x00FFFFFF)]);
      final ui.Image gloss = await _gloss(160);
      final List<ui.Image> bl = await _ballLight(96);
      ready = DfSprites._(shadow, dot, gloss, bl[0], bl[1]);
      return ready;
    } catch (_) {
      return null;
    }
  }

  static Future<ui.Image> _radial(int n, List<double> stops, List<ui.Color> cols) {
    final ui.PictureRecorder rec = ui.PictureRecorder();
    final ui.Canvas c = ui.Canvas(rec);
    final double r = n / 2;
    final ui.Paint p = ui.Paint()..shader = ui.Gradient.radial(ui.Offset(r, r), r, cols, stops);
    c.drawRect(ui.Rect.fromLTWH(0, 0, n.toDouble(), n.toDouble()), p);
    return rec.endRecording().toImage(n, n);
  }

  /// Subtle specular sheen + thin top-left rim arc (render.ts sprites().gloss / match_view.gd _gloss_tex).
  static Future<ui.Image> _gloss(int n) {
    final ui.PictureRecorder rec = ui.PictureRecorder();
    final ui.Canvas c = ui.Canvas(rec);
    final double big = n / 2;
    final double r = big - 2;
    final ui.Offset ctr = ui.Offset(big, big);
    final ui.Offset hot = ui.Offset(big - r * 0.38, big - r * 0.48);
    c.save();
    c.clipPath(ui.Path()..addOval(ui.Rect.fromCircle(center: ctr, radius: r * 0.97)));
    c.drawRect(
      ui.Rect.fromLTWH(0, 0, n.toDouble(), n.toDouble()),
      ui.Paint()
        ..shader = ui.Gradient.radial(hot, r * 0.9, const <ui.Color>[ui.Color(0x42FFFFFF), ui.Color(0x0DFFFFFF), ui.Color(0x00FFFFFF)],
            const <double>[0, 0.45, 1]),
    );
    c.restore();
    final double a0 = (205 - 360) * math.pi / 180;
    final double a1 = (265 - 360) * math.pi / 180;
    c.drawArc(
      ui.Rect.fromCircle(center: ctr, radius: r * 0.93),
      a0,
      a1 - a0,
      false,
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = ui.StrokeCap.round
        ..color = const ui.Color(0x61FFFFFF),
    );
    return rec.endRecording().toImage(n, n);
  }

  /// Bake ball.gdshader's lighting (light from the top-left) into a multiply and an additive sprite.
  static Future<List<ui.Image>> _ballLight(int n) async {
    final Uint8List mul = Uint8List(n * n * 4);
    final Uint8List add = Uint8List(n * n * 4);
    final double lx0 = -0.42, ly0 = -0.55, lz0 = 0.72;
    final double ll = math.sqrt(lx0 * lx0 + ly0 * ly0 + lz0 * lz0);
    final double lx = lx0 / ll, ly = ly0 / ll, lz = lz0 / ll;
    double hx = lx, hy = ly, hz = lz + 1;
    final double hl = math.sqrt(hx * hx + hy * hy + hz * hz);
    hx /= hl;
    hy /= hl;
    hz /= hl;
    final double aon = math.sqrt(0.5 * 0.5 + 0.7 * 0.7);
    for (int y = 0; y < n; y++) {
      for (int x = 0; x < n; x++) {
        final double px = (x + 0.5) / n * 2 - 1;
        final double py = (y + 0.5) / n * 2 - 1;
        final double d = math.sqrt(px * px + py * py);
        final int i = (y * n + x) * 4;
        if (d > 1) continue;
        final double z = math.sqrt(math.max(0.0, 1 - d * d));
        final double ndl = math.max(0.0, px * lx + py * ly + z * lz);
        final double dif = 0.62 + 0.5 * ndl;
        final double ndh = math.max(0.0, px * hx + py * hy + z * hz);
        final double spec = math.pow(ndh, 36).toDouble() * 0.55 + math.pow(ndh, 220).toDouble() * 0.6;
        final double rim = math.pow(1 - z, 2.5).toDouble();
        final double t = ((px * 0.5 + py * 0.7) / aon - 0.2) / 0.8;
        final double tc = t < 0 ? 0 : (t > 1 ? 1 : t);
        final double ao = 1 - 0.18 * tc * tc * (3 - 2 * tc);
        final double m = dif * ao * (1 - 0.45 * rim);
        final double edge = ((1 - d) / 0.04).clamp(0.0, 1.0).toDouble();
        final int mv = (math.min(1.0, m) * 255).round();
        mul[i] = mv;
        mul[i + 1] = mv;
        mul[i + 2] = mv;
        mul[i + 3] = (edge * 255).round();
        // brightening part of the diffuse term (> 1) goes into the additive sprite as a soft white
        final double extra = math.max(0.0, m - 1) * 0.35;
        final double ar = math.min(1.0, spec + extra + 0.35 * rim * 0.18);
        final double ag = math.min(1.0, spec + extra + 0.6 * rim * 0.18);
        final double ab = math.min(1.0, spec + extra + 1.0 * rim * 0.18);
        add[i] = (ar * 255 * edge).round();
        add[i + 1] = (ag * 255 * edge).round();
        add[i + 2] = (ab * 255 * edge).round();
        add[i + 3] = 255;
      }
    }
    final ui.Image a = await _fromPixels(mul, n);
    final ui.Image b = await _fromPixels(add, n);
    return <ui.Image>[a, b];
  }

  static Future<ui.Image> _fromPixels(Uint8List px, int n) {
    final Completer<ui.Image> c = Completer<ui.Image>();
    ui.decodeImageFromPixels(px, n, n, ui.PixelFormat.rgba8888, c.complete);
    return c.future;
  }
}

/// Field art with soft feathered edges (field.gdshader: 6% top/bottom, 5% left/right), baked once.
Future<ui.Image?> dfFeatherField(ui.Image src) async {
  try {
    final int w = src.width;
    final int h = src.height;
    final ui.PictureRecorder rec = ui.PictureRecorder();
    final ui.Canvas c = ui.Canvas(rec);
    final ui.Rect r = ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
    c.saveLayer(r, ui.Paint());
    c.drawImage(src, ui.Offset.zero, ui.Paint()..filterQuality = ui.FilterQuality.medium);
    c.drawRect(
      r,
      ui.Paint()
        ..blendMode = ui.BlendMode.dstIn
        ..shader = ui.Gradient.linear(ui.Offset.zero, ui.Offset(0, h.toDouble()),
            const <ui.Color>[ui.Color(0x00FFFFFF), ui.Color(0xFFFFFFFF), ui.Color(0xFFFFFFFF), ui.Color(0x00FFFFFF)],
            const <double>[0, 0.06, 0.94, 1]),
    );
    c.drawRect(
      r,
      ui.Paint()
        ..blendMode = ui.BlendMode.dstIn
        ..shader = ui.Gradient.linear(ui.Offset.zero, ui.Offset(w.toDouble(), 0),
            const <ui.Color>[ui.Color(0x00FFFFFF), ui.Color(0xFFFFFFFF), ui.Color(0xFFFFFFFF), ui.Color(0x00FFFFFF)],
            const <double>[0, 0.05, 0.95, 1]),
    );
    c.restore();
    return await rec.endRecording().toImage(w, h);
  } catch (_) {
    return null;
  }
}
