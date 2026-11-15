// v0.7.0 Flame component tree of a match (hosted by MatchGame in ../game.dart, shown through GameWidget).
//
//   MatchGame (FlameGame)
//    ├─ FixedStepDriver      (-100) update: feeds the frame dt to the deterministic engine; the engine's accumulator
//    │                              runs lib/game/physics at its fixed 240 Hz step (Engine.update / NetMatch)
//    ├─ FrameClock            (-90) update: per-frame render state (interpolation alpha, net ripple, visual spin)
//    ├─ SoftCamera            (-80) update: calm critically-damped camera offset (frozen while aiming)
//    ├─ BackgroundComponent     (0) render: baked stadium + pitch art (screen space)
//    ├─ PitchSpace             (10) renderTree: world transform (flip, view offset + camera, scale), then children:
//    │    ├─ GoalNetsComponent        (10)  nets behind everything
//    │    ├─ DropShadowsComponent     (20)  soft black disc shadows
//    │    ├─ DiscsComponent           (30)  discs, gloss, turn rings
//    │    ├─ BallTrailComponent       (40)  trail + speed streaks
//    │    ├─ BallComponent            (50)  ball halo, black drop shadow, textured rolling sphere (damped visual roll)
//    │    ├─ GoalFramesComponent      (60)  3D posts, crossbar, back frame, side/roof nets
//    │    ├─ AimComponent             (70)  aim arrow + physics trajectory preview
//    │    └─ ParticlesComponent       (80)  sparks / confetti
//    └─ FlashComponent        (100) render: goal flash (screen space)
//
// Every layer paints through MatchRenderer (../render.dart), which keeps the batched atlas / mesh drawing (one draw
// call per layer). Nothing here touches the simulation: positions are read from the engine and interpolated with
// the accumulator's alpha, so the display is smooth at any frame rate while lockstep stays bit-exact.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';

import '../engine.dart';
import '../game.dart';
import '../render.dart';

/// Base for a layer that paints only once the renderer is ready.
abstract class _Layer extends Component with HasGameReference<MatchGame> {
  _Layer({super.priority});
  MatchRenderer? get r => game.r;
}

/// Feeds Flame's frame time into the engine (offline Engine.update, online NetMatch); the engine accumulates it and
/// runs whole 1/240 s physics steps, so the simulation never depends on the frame rate.
class FixedStepDriver extends _Layer {
  FixedStepDriver() : super(priority: -100);
  @override
  void update(double dt) => game.driveFrame(dt);
}

class FrameClock extends _Layer {
  FrameClock() : super(priority: -90);
  @override
  void update(double dt) => r?.beginFrame(game.time);
}

/// Calm camera: drifts at most [maxPx] logical px towards the moving ball (critically damped, ~0.7 s), stays still
/// while a shot is being aimed so the arrow never swims under the finger, and eases back to centre at rest.
class SoftCamera extends _Layer {
  SoftCamera() : super(priority: -80);
  static const double maxPx = 7, k = 4.2;
  double x = 0, y = 0, _vx = 0, _vy = 0;

  @override
  void update(double dt) {
    final rr = r;
    if (rr == null || dt <= 0) return;
    final e = game.e;
    var tx = 0.0, ty = 0.0;
    if (e.drag == null && e.phase == Phase.move) {
      final b = e.ball, al = rr.frameAlpha;
      final bx = b.px + (b.x - b.px) * al, by = b.py + (b.y - b.py) * al;
      final sx = (e.Fr - e.Fl) / 2, sy = (e.Fb - e.Ft) / 2;
      tx = -((bx - e.CX) / sx).clamp(-1.0, 1.0) * maxPx;
      ty = -((by - e.CY) / sy).clamp(-1.0, 1.0) * maxPx;
    } else if (e.drag != null) {
      tx = x;
      ty = y;
    }
    // critically damped spring (no overshoot)
    final h = math.min(dt, 1 / 30);
    _vx += (-2 * k * _vx - k * k * (x - tx)) * h;
    _vy += (-2 * k * _vy - k * k * (y - ty)) * h;
    x += _vx * h;
    y += _vy * h;
  }
}

class BackgroundComponent extends _Layer {
  BackgroundComponent() : super(priority: 0);
  @override
  void render(ui.Canvas canvas) => r?.paintBackground(canvas);
}

/// The world (pitch) coordinate space: its children paint in engine units.
class PitchSpace extends _Layer {
  PitchSpace() : super(priority: 10);

  @override
  Future<void> onLoad() async {
    await addAll([
      GoalNetsComponent(),
      DropShadowsComponent(),
      DiscsComponent(),
      BallTrailComponent(),
      BallComponent(),
      GoalFramesComponent(),
      AimComponent(),
      ParticlesComponent(),
    ]);
  }

  @override
  void renderTree(ui.Canvas canvas) {
    final rr = r;
    if (rr == null) return;
    canvas.save();
    rr.applyWorld(canvas, camX: game.softCam.x, camY: game.softCam.y);
    super.renderTree(canvas);
    canvas.restore();
  }
}

class GoalNetsComponent extends _Layer {
  GoalNetsComponent() : super(priority: 10);
  @override
  void render(ui.Canvas canvas) => r?.paintNets(canvas);
}

class DropShadowsComponent extends _Layer {
  DropShadowsComponent() : super(priority: 20);
  @override
  void render(ui.Canvas canvas) => r?.paintShadows(canvas);
}

class DiscsComponent extends _Layer {
  DiscsComponent() : super(priority: 30);
  @override
  void render(ui.Canvas canvas) => r?.paintDiscs(canvas);
}

class BallTrailComponent extends _Layer {
  BallTrailComponent() : super(priority: 40);
  @override
  void render(ui.Canvas canvas) => r?.paintTrail(canvas);
}

class BallComponent extends _Layer {
  BallComponent() : super(priority: 50);
  @override
  void render(ui.Canvas canvas) => r?.paintBall(canvas);
}

class GoalFramesComponent extends _Layer {
  GoalFramesComponent() : super(priority: 60);
  @override
  void render(ui.Canvas canvas) => r?.paintGoalFrames(canvas);
}

class AimComponent extends _Layer {
  AimComponent() : super(priority: 70);
  @override
  void render(ui.Canvas canvas) => r?.paintAim(canvas);
}

class ParticlesComponent extends _Layer {
  ParticlesComponent() : super(priority: 80);
  @override
  void render(ui.Canvas canvas) => r?.paintParticles(canvas);
}

class FlashComponent extends _Layer {
  FlashComponent() : super(priority: 100);
  @override
  void render(ui.Canvas canvas) => r?.paintFlash(canvas);
}
