// Shared Flame host for NEXORA's physics games (Flame F1).
//
// The games keep their pure-Dart deterministic engines; Flame only owns the frame loop, the
// rendering surface and the effects layer:
//  * [NxFlameHost.advance] turns Flame's variable frame dt into fixed simulation steps
//    (accumulator, big-dt clamp, step cap), so physics never depends on the frame rate.
//  * [NxPainterLayer] renders the game's existing CustomPainter through a Flame Component, on
//    the same logical-pixel canvas the CustomPaint had, so the visuals are unchanged.
//  * [NxFx] (see nx_fx.dart) sits above it for bursts, spark rings and the fire trail.
// The background is transparent so table / field art and Flutter widgets behind it show through.
// FlameGame already pauses its loop when the app is backgrounded (pauseWhenBackgrounded).
import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/rendering.dart' show CustomPainter;

import 'nx_fx.dart';

/// One fixed simulation step of [NxFlameHost.step] seconds.
typedef NxStepFn = void Function(double step);

/// Once per rendered frame, after the fixed steps of that frame.
typedef NxFrameFn = void Function(double dt);

class NxFlameHost extends FlameGame {
  NxFlameHost({
    this.onStep,
    this.onFrame,
    this.step = 1 / 120,
    this.maxFrameDt = 0.05,
    this.maxStepsPerFrame = 8,
    this.rawFrameDt = false,
    this.painter,
    NxFxConfig fxConfig = const NxFxConfig(),
  })  : assert(step > 0),
        assert(maxStepsPerFrame > 0),
        fx = NxFx(fxConfig) {
    pauseWhenBackgrounded = true;
  }

  /// Fixed-step simulation callback (null: the game has its own accumulator inside its engine).
  NxStepFn? onStep;

  /// Per-frame callback (bots, timers, HUD, animations). Gets the clamped dt unless [rawFrameDt].
  NxFrameFn? onFrame;

  /// Simulation step in seconds (1/120 by default, same as billiards/carrom cores).
  final double step;

  /// A frame longer than this (hitch, debugger, resume) only advances the simulation this much.
  final double maxFrameDt;

  /// Hard cap of steps per frame so a slow phone can never spiral.
  final int maxStepsPerFrame;

  /// Pass the unclamped frame dt to [onFrame] (for engines that clamp it themselves).
  final bool rawFrameDt;

  /// The scene painter drawn every frame by [NxPainterLayer]. Swap it freely (theme changes).
  CustomPainter? painter;

  /// Effects layer (particles, rings, fire). Always above the painter.
  final NxFx fx;

  /// Wall-clock seconds this host has run (sum of raw frame dts; stops while paused).
  double clock = 0;

  /// Unsimulated time carried to the next frame (always < [step] after [advance]).
  double accumulator = 0;

  /// Total fixed steps run so far.
  int totalSteps = 0;

  /// Interpolation factor between the last two steps (0..1), for renderers that want it.
  double get alpha => accumulator / step;

  @override
  Color backgroundColor() => const Color(0x00000000);

  @override
  Future<void> onLoad() async {
    await add(NxPainterLayer());
    await add(fx);
  }

  /// Advances the clock by one frame of [rawDt] seconds: runs the fixed steps, then [onFrame].
  /// Returns how many fixed steps ran. Pure logic (no rendering), unit-tested.
  int advance(double rawDt) {
    final double raw = (rawDt.isNaN || rawDt < 0) ? 0 : rawDt;
    clock += raw;
    final double dt = math.min(raw, maxFrameDt);
    int n = 0;
    final NxStepFn? s = onStep;
    if (s != null) {
      accumulator += dt;
      while (accumulator >= step && n < maxStepsPerFrame) {
        accumulator -= step;
        n++;
        s(step);
      }
      // Cap hit: drop the backlog instead of carrying a debt into the next frames.
      if (accumulator >= step) accumulator %= step;
      totalSteps += n;
    }
    onFrame?.call(rawFrameDt ? raw : dt);
    return n;
  }

  @override
  void update(double dt) {
    advance(dt);
    super.update(dt);
  }
}

/// Renders [NxFlameHost.painter] on the game canvas (logical pixels, origin top-left),
/// exactly like the CustomPaint it replaces.
class NxPainterLayer extends Component with HasGameReference<NxFlameHost> {
  NxPainterLayer() : super(priority: 0);

  Size _size = Size.zero;

  @override
  void render(Canvas canvas) {
    final CustomPainter? p = game.painter;
    if (p == null) return;
    final Vector2 s = game.size;
    if (s.x <= 0 || s.y <= 0) return;
    if (_size.width != s.x || _size.height != s.y) _size = Size(s.x, s.y);
    p.paint(canvas, _size);
  }
}
