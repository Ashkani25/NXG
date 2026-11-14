// =====================================================================================================
// DiscMatchView — Flutter port of the Godot build's src/game/match_view.gd (MatchView).
//
// Renders an [Engine] (offline match, online host) or an externally supplied body list (online
// clients) with: blurred stadium backdrop, feathered field art + neon outline + corner arcs, soft
// shadows, additive glows + disc motion trails (fancy), glowing turn rings, discs (team skin, side
// band, gloss, rim light, dimmed when not on turn), additive ball trail, the ball as a lit rotating
// 3D sphere (texture mapped through the engine's 3x3 rotation matrix), goal art (bottom mirrored)
// with net shake, goal ripple light, the code-drawn gradient aim arrow + accuracy dots, engine
// particles, impact sparks + goal confetti, camera shake/zoom on goals (slow-mo comes from the
// engine), screen flash. Every body is drawn at prev -> current interpolated by engine.alpha().
//
// PUBLIC API
//   final DiscMatchController ctrl = DiscMatchController();
//   DiscMatchView(
//     engine: engine,                 // required Engine (positions, phase, drag/aim, fx state)
//     controller: ctrl,               // optional: toWorld/toScreen, onEvent, setSkin, bodiesOverride
//     ballSkin: 3,                    // ball art index 0..35 (default engine.cfg.ball)
//     teamIds: <String>['club0', 'nat2'], // disc skin per side (default engine.cfg.teams)
//     fancy: true,                    // false = "low"/smooth quality (no glows, sparks, confetti, zoom)
//     flipped: false,                 // online: rotate 180° so team 1's own goal is at the bottom
//     myTeam: -1,                     // which side gets the blue "me" ring (-1: 1 if flipped else 0)
//     topInset: 120, bottomInset: 40, // screen px kept free above/below the pitch (HUD etc.)
//     bodiesOverride: null,           // List<Offset?> world positions by engine.bodies index (online)
//     onTick: (double dt) { ... },    // called every frame BEFORE painting (step the engine here)
//   )
//   ctrl.toWorld(localPos) / ctrl.toScreen(worldPos)  // view-local px <-> world (flip aware)
//   ctrl.onEvent(ev)                  // forward engine events for sparks / confetti
//   ctrl.setSkin(ball: 4, side: 0, teamId: 'lux3')     // visual-only skin swap
//   ctrl.bodiesOverride = list        // per-frame override without rebuilding the widget
//   ctrl.engine = otherEngine         // swap the rendered engine (set_engine)
// Wrap the view in a Listener and convert pointer positions with ctrl.toWorld (same local space).
// =====================================================================================================
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../core/data.dart';
import '../core/engine.dart';
import 'df_images.dart';
import 'disc_match_painter.dart';

/// Handle to a mounted [DiscMatchView].
class DiscMatchController {
  DfRender? _r;
  List<Offset?>? _override;

  /// World positions by engine.bodies index (null entries / null list = engine positions).
  List<Offset?>? get bodiesOverride => _override;
  set bodiesOverride(List<Offset?>? v) {
    _override = v;
    _r?.override = v;
  }

  bool get attached => _r != null;

  set engine(Engine e) {
    final DfRender? r = _r;
    if (r != null) r.setEngine(e);
  }

  Offset toWorld(Offset p) => _r?.toWorld(p) ?? p;
  Offset toScreen(Offset w) => _r?.toScreen(w) ?? w;

  /// Current pitch scale (screen px per world unit).
  double get scale => _r?.s ?? 1;

  void onEvent(EngineEvent ev) => _r?.onEvent(ev);

  void setSkin({int ball = -1, int side = 0, String teamId = ''}) => _r?.setSkin(ball: ball, side: side, teamId: teamId);
}

class DiscMatchView extends StatefulWidget {
  const DiscMatchView({
    super.key,
    required this.engine,
    this.controller,
    this.ballSkin,
    this.teamIds,
    this.fancy = true,
    this.flipped = false,
    this.myTeam = -1,
    this.topInset = 0,
    this.bottomInset = 0,
    this.bodiesOverride,
    this.onTick,
  });

  final Engine engine;
  final DiscMatchController? controller;
  final int? ballSkin;
  final List<String>? teamIds;
  final bool fancy;
  final bool flipped;
  final int myTeam;
  final double topInset;
  final double bottomInset;
  final List<Offset?>? bodiesOverride;
  final void Function(double dt)? onTick;

  @override
  State<DiscMatchView> createState() => _DiscMatchViewState();
}

class _DiscMatchViewState extends State<DiscMatchView> with SingleTickerProviderStateMixin {
  late final DfRender _r;
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _r = DfRender(
      engine: widget.engine,
      ballIdx: widget.ballSkin ?? widget.engine.cfg.ball,
      teamIds: widget.teamIds ?? widget.engine.cfg.teams,
      fancy: widget.fancy,
      flipped: widget.flipped,
      myTeam: widget.myTeam,
    );
    _r.override = widget.bodiesOverride ?? widget.controller?._override;
    widget.controller?._r = _r;
    _r.loadAll();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    double dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (dt < 0) dt = 0;
    if (dt > 0.1) dt = 0.1;
    widget.onTick?.call(dt);
    if (!mounted) return;
    _r.tick(dt);
  }

  @override
  void didUpdateWidget(covariant DiscMatchView old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      if (old.controller?._r == _r) old.controller?._r = null;
      widget.controller?._r = _r;
    }
    if (!identical(old.engine, widget.engine)) _r.setEngine(widget.engine);
    if (widget.bodiesOverride != null || old.bodiesOverride != null) _r.override = widget.bodiesOverride;
    if (old.fancy != widget.fancy) _r.fancy = widget.fancy;
    _r.flipped = widget.flipped;
    _r.myTeam = widget.myTeam;
    if (widget.ballSkin != null && widget.ballSkin != old.ballSkin) _r.setSkin(ball: widget.ballSkin!);
    final List<String>? t = widget.teamIds;
    if (t != null && t.length >= 2) {
      _r.setSkin(side: 0, teamId: t[0]);
      _r.setSkin(side: 1, teamId: t[1]);
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    if (widget.controller?._r == _r) widget.controller?._r = null;
    _r.disposeImages();
    _r.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
        final Size size = Size(c.maxWidth.isFinite ? c.maxWidth : 400, c.maxHeight.isFinite ? c.maxHeight : 700);
        _r.fit(size, widget.topInset, widget.bottomInset);
        return SizedBox(
          width: size.width,
          height: size.height,
          child: Stack(children: <Widget>[
            Positioned.fill(
              child: RepaintBoundary(child: CustomPaint(painter: DfBackdropPainter(_r, repaint: _r.backdrop))),
            ),
            Positioned.fill(child: CustomPaint(painter: DfWorldPainter(_r, repaint: _r))),
          ]),
        );
      }),
    );
  }
}

/// A ChangeNotifier anyone may fire.
class DfBump extends ChangeNotifier {
  void bump() => notifyListeners();
}

/// Short-lived view-only particle (impact sparks k=0, goal confetti k=1).
class DfFx {
  DfFx(this.x, this.y, this.vx, this.vy, this.life, this.size, this.color, this.k, this.damp, this.rot, this.vr);
  double x;
  double y;
  double vx;
  double vy;
  double l = 0;
  final double life;
  final double size;
  final Color color;
  final int k;
  final double damp;
  double rot;
  final double vr;
}

/// Render state + per-frame logic of a DiscMatchView (read by the painters).
class DfRender extends ChangeNotifier {
  DfRender({
    required Engine engine,
    required this.ballIdx,
    required List<String> teamIds,
    required this.fancy,
    required this.flipped,
    required this.myTeam,
  })  : e = engine,
        teamIds = <String>[teamIds.isNotEmpty ? teamIds[0] : 'club0', teamIds.length > 1 ? teamIds[1] : 'club1'] {
    trailCols = _trailCols(ballIdx);
  }

  Engine e;
  int ballIdx;
  final List<String> teamIds;
  bool fancy;
  bool flipped;
  int myTeam;
  List<Offset?>? override;

  /// Repaints the static backdrop (layout / field art changes only).
  final DfBump backdrop = DfBump();

  ui.Image? fieldImg; // feathered
  ui.Image? fieldRaw;
  ui.Image? ballImg;
  ui.Image? goalImg;
  final List<ui.Image?> teamImg = <ui.Image?>[null, null];
  DfSprites? sp = DfSprites.ready;
  bool _disposed = false;

  double W = 0, H = 0, s = 1, ox = 0, oy = 0, t = 0;
  double _top = -1, _bottom = -1;
  List<Offset> pos = <Offset>[];
  Offset shk = Offset.zero;
  double zoom = 0;
  List<Color> trailCols = <Color>[];
  final List<DfFx> fx = <DfFx>[];
  final math.Random _rnd = math.Random();

  // aim smoothing (match_view.gd _aim_*)
  bool aimOn = false;
  double aimUx = 0, aimUy = -1, aimP = 0;

  static List<Color> _trailCols(int i) {
    final List<int> c = kTrails[i % kTrails.length].c;
    return <Color>[Color(c[0]), Color(c.length > 1 ? c[1] : c[0]), Color(c.length > 2 ? c[2] : 0xFFFFFFFF)];
  }

  void setEngine(Engine en) {
    final bool fieldChanged = en.cfg.field != e.cfg.field;
    e = en;
    pos = <Offset>[];
    if (fieldChanged) _loadField();
    _top = -1;
  }

  void loadAll() {
    DfSprites.load().then((DfSprites? v) {
      if (_disposed) return;
      sp = v;
      backdrop.bump();
    });
    _loadField();
    dfLoadImage(DfArt.ball(ballIdx), width: 256).then((ui.Image? i) {
      if (!_disposed) ballImg = i;
    });
    dfLoadImage(DfArt.goal(e.f.gs), width: 840).then((ui.Image? i) {
      if (!_disposed) goalImg = i;
    });
    for (int k = 0; k < 2; k++) {
      _loadTeam(k);
    }
  }

  void _loadTeam(int k) {
    final String id = teamIds[k];
    dfLoadImage(DfArt.team(id), width: 192).then((ui.Image? i) {
      if (!_disposed && teamIds[k] == id) teamImg[k] = i;
    });
  }

  void _loadField() {
    final int fi = e.cfg.field;
    dfLoadImage(DfArt.field(fi), cache: false).then((ui.Image? raw) async {
      if (_disposed || raw == null) {
        raw?.dispose();
        return;
      }
      final ui.Image? feathered = await dfFeatherField(raw);
      if (_disposed) {
        raw.dispose();
        feathered?.dispose();
        return;
      }
      fieldRaw?.dispose();
      fieldImg?.dispose();
      fieldRaw = raw;
      fieldImg = feathered ?? raw;
      if (identical(fieldImg, fieldRaw)) fieldRaw = null;
      backdrop.bump();
    });
  }

  void disposeImages() {
    _disposed = true;
    fieldImg?.dispose();
    if (!identical(fieldRaw, fieldImg)) fieldRaw?.dispose();
    fieldImg = null;
    fieldRaw = null;
    backdrop.dispose();
  }

  /// Swap the ball skin and/or one side's disc skin (visual only). ball < 0 keeps the ball.
  void setSkin({int ball = -1, int side = 0, String teamId = ''}) {
    if (ball >= 0 && ball != ballIdx) {
      ballIdx = ball;
      trailCols = _trailCols(ball);
      dfLoadImage(DfArt.ball(ball), width: 256).then((ui.Image? i) {
        if (!_disposed && ballIdx == ball) ballImg = i;
      });
    }
    if (teamId.isNotEmpty && side >= 0 && side < 2 && teamId != teamIds[side]) {
      teamIds[side] = teamId;
      _loadTeam(side);
    }
  }

  // ------------------------------------------------------------------ layout (RN computeView)
  void fit(Size size, double top, double bottom) {
    if (size.width == W && size.height == H && top == _top && bottom == _bottom) return;
    W = size.width;
    H = size.height;
    _top = top;
    _bottom = bottom;
    final Field f = e.f;
    final double playH = math.max(300.0, H - top - bottom);
    s = math.min(W / (f.r - f.l + 56 * kFS), playH / ((f.b - f.t) + 2 * e.gg.h + 48)) * 0.99;
    ox = W / 2 - e.cx * s;
    oy = top + playH / 2 - e.cy * s;
    backdrop.bump();
  }

  Offset toWorld(Offset p) {
    final Offset q = flipped ? Offset(W - p.dx, H - p.dy) : p;
    return Offset((q.dx - ox) / s, (q.dy - oy) / s);
  }

  Offset toScreen(Offset w) {
    final Offset p = Offset(ox + w.dx * s, oy + w.dy * s);
    return flipped ? Offset(W - p.dx, H - p.dy) : p;
  }

  /// Visible world rect, inset by [m] world units.
  Rect visRect(double m) {
    final Offset a = toWorld(Offset.zero);
    final Offset b = toWorld(Offset(W, H));
    final Rect r = Rect.fromPoints(a, b);
    return r.deflate(m);
  }

  Color ringColor(int team) {
    final int me = myTeam >= 0 ? myTeam : (flipped ? 1 : 0);
    return team == me ? const Color(0xFF3BA8FF) : const Color(0xFFFF4A5A);
  }

  Offset ballPos() {
    final int i = e.bodies.indexOf(e.ball);
    if (i >= 0 && i < pos.length) return pos[i];
    return Offset(e.ball.x, e.ball.y);
  }

  // ------------------------------------------------------------------ frame
  void tick(double dt) {
    t += dt;
    final double al = e.alpha();
    final int n = e.bodies.length;
    if (pos.length != n) pos = List<Offset>.filled(n, Offset.zero);
    final double smk = (dt * 30.0).clamp(0.2, 1.0).toDouble();
    final List<Offset?> ov = override ?? const <Offset?>[];
    for (int i = 0; i < n; i++) {
      final Body b = e.bodies[i];
      final Offset? o = i < ov.length ? ov[i] : null;
      final Offset tgt = o ?? Offset(b.px + (b.x - b.px) * al + b.vox, b.py + (b.y - b.py) * al + b.voy);
      final Offset cur = pos[i];
      if (cur == Offset.zero || o == null || (cur - tgt).distanceSquared > 250.0 * 250.0) {
        pos[i] = tgt;
      } else {
        pos[i] = Offset.lerp(cur, tgt, smk)!;
      }
    }
    if (!fancy && e.parts.length > 40) e.parts.length = 40;
    final double k = W / 415.0;
    shk = Offset.zero;
    if (e.cam > 0.05 && e.flash > 0) {
      shk = Offset(_rnd.nextDouble() - 0.5, _rnd.nextDouble() - 0.5) * (e.cam * 4.2 * k);
    }
    zoom = fancy ? 0.007 * math.min(e.cam, 1.4) : 0.0;
    _tickFx(dt);
    notifyListeners();
  }

  // ------------------------------------------------------------------ view-only sparks / confetti
  void onEvent(EngineEvent ev) {
    if (!fancy) return;
    switch (ev.t) {
      case 'hit':
        if (ev.ball && ev.power > 0.3) _spark(ballPos(), ev.power);
        break;
      case 'post':
        if (ev.power > 0.25) _spark(ballPos(), ev.power);
        break;
      case 'goal':
        if (!ev.nogoal && ev.team >= 0 && ev.team < 2) _confetti(e.ball.x, e.goals[ev.team].y, -e.goals[ev.team].d.toDouble());
        break;
      default:
        break;
    }
  }

  void _spark(Offset p, double pw) {
    if (fx.length > 400) return;
    final int n = (10 + pw * 30).clamp(10, 36).toInt();
    for (int i = 0; i < n; i++) {
      final double a = _rnd.nextDouble() * math.pi * 2;
      final double v = 260 + _rnd.nextDouble() * 440;
      fx.add(DfFx(p.dx, p.dy, math.cos(a) * v, math.sin(a) * v, 0.45 * (0.8 + _rnd.nextDouble() * 0.2),
          64 * (0.12 + _rnd.nextDouble() * 0.18), const Color(0xFFFFFFFF), 0, 900 + _rnd.nextDouble() * 500, 0, 0));
    }
  }

  void _confetti(double x, double y, double dirY) {
    for (int i = 0; i < 110; i++) {
      final double a = _rnd.nextDouble() * math.pi * 2;
      final double v = 240 + _rnd.nextDouble() * 580;
      final int ci = _rnd.nextInt(kGoalCols.length);
      fx.add(DfFx(x, y, math.cos(a) * v, math.sin(a) * v + dirY * 60, 2.0 * (0.92 + _rnd.nextDouble() * 0.08),
          0.8 + _rnd.nextDouble() * 0.8, Color(kGoalCols[ci]), 1, 120 + _rnd.nextDouble() * 140, _rnd.nextDouble() * math.pi * 2,
          (_rnd.nextDouble() * 2 - 1) * 4 * math.pi));
    }
  }

  void _tickFx(double dt) {
    int w = 0;
    for (int i = 0; i < fx.length; i++) {
      final DfFx p = fx[i];
      p.l += dt;
      if (p.l >= p.life) continue;
      final double sp0 = math.sqrt(p.vx * p.vx + p.vy * p.vy);
      if (sp0 > 0) {
        final double ns = math.max(0.0, sp0 - p.damp * dt);
        p.vx *= ns / sp0;
        p.vy *= ns / sp0;
      }
      if (p.k == 1) p.vy += 700 * dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.rot += p.vr * dt;
      fx[w++] = p;
    }
    fx.length = w;
  }
}
