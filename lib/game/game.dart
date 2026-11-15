// Flame host for a match (v0.7.0): a FlameGame whose component tree (flame/match_components.dart) drives the
// deterministic engine from Flame's update and paints the match as layered components. The simulation step itself
// is injected (offline: Engine.update; online: the net controller), and the engine's accumulator runs
// lib/game/physics at its fixed 240 Hz step; components only read and interpolate.
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';

import 'engine.dart';
import 'flame/match_components.dart';
import 'render.dart';

class MatchGame extends FlameGame {
  final Engine e;
  MatchRenderer? r;
  final void Function(double dt) onTick;
  double _t = 0;
  bool paused = false;
  late final SoftCamera softCam = SoftCamera();

  // perf probes for the debug overlay
  double frameMs = 0, stepMs = 0;
  final Stopwatch _sw = Stopwatch();

  MatchGame({required this.e, required this.onTick});

  MatchView? get view => r?.v;

  /// render clock (smoothed frame time, seconds since the match opened)
  double get time => _t;

  @override
  ui.Color backgroundColor() => const ui.Color(0xff02040c);

  @override
  Future<void> onLoad() async {
    await addAll([FixedStepDriver(), FrameClock(), softCam, BackgroundComponent(), PitchSpace(), FlashComponent()]);
  }

  // v5 smoother motion: vsync deltas jitter by a few ms on Android, which makes the fixed-step interpolation stutter.
  // A light low-pass on dt evens the frame pacing; real hitches (> 2x the average) pass through unfiltered so the
  // simulation never drifts from wall-clock time for more than a frame.
  // v6: the time the filter holds back (or runs ahead) is carried and paid back a little each frame, so the
  // simulation stays locked to wall-clock time (no slow drift) while the per-frame step stays even.
  double _dtAvg = 1 / 60, _carry = 0;
  double _smooth(double dt) {
    if (dt <= 0) return dt;
    if (dt > _dtAvg * 2 || dt < _dtAvg * .5) {
      _dtAvg = _dtAvg * .7 + dt.clamp(1 / 240, 1 / 20) * .3;
      _carry = 0;
      return dt;
    }
    _dtAvg = _dtAvg * .85 + dt * .15;
    _carry += dt - _dtAvg;
    final pay = _carry.clamp(-_dtAvg * .1, _dtAvg * .1);
    _carry -= pay;
    return _dtAvg + pay;
  }

  /// Called by [FixedStepDriver] (first component in the update order) once per Flame frame.
  void driveFrame(double rawDt) {
    final dt = _smooth(rawDt);
    _t += dt;
    if (!paused) {
      _sw
        ..reset()
        ..start();
      onTick(dt);
      _sw.stop();
      stepMs = stepMs * .9 + _sw.elapsedMicroseconds / 1000 * .1;
    }
    frameMs = frameMs * .9 + rawDt * 1000 * .1;
  }

  /// screen (logical px) -> world units, through the same transform the pitch space paints with (incl. soft camera)
  Offset? toWorld(Offset p) {
    final v = r?.v;
    if (v == null) return null;
    var x = p.dx, y = p.dy;
    if (v.flipped) {
      x = v.W - x;
      y = v.H - y;
    }
    return Offset((x - v.ox - softCam.x) / v.s, (y - v.oy - softCam.y) / v.s);
  }
}
