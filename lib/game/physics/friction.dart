// Sliding friction of a disc / the ball on the cloth.
//
// Model: dv/dt = -roll - damp * v along the direction of motion (exponential damping + a small constant rolling
// resistance). It is integrated with its EXACT flow, v(t + h) = (v + roll/damp) * e^(-damp h) - roll/damp, so the
// result does not depend on how a step is split into substeps (flows compose exactly). Below vSleep the body sleeps:
// its velocity is set to exactly zero and it stays put until an impulse wakes it.
import 'dart:math' as math;

import '../fdlibm.dart';
import 'body.dart';
import 'physics_config.dart';

/// speed after time h from speed v (exact flow), never negative
double decaySpeed(double v, double h, double damp, double roll) {
  if (damp <= 0) return math.max(0, v - roll * h);
  final c = roll / damp;
  final nv = (v + c) * fexp(-damp * h) - c;
  return nv > 0 ? nv : 0;
}

/// apply friction to [b] over [h]; returns true when the body is (now) asleep
bool applyFriction(Body b, double h, PhysicsConfig c) {
  if (b.vx == 0 && b.vy == 0) return true;
  final sp = math.sqrt(b.vx * b.vx + b.vy * b.vy);
  final ball = b.isBall;
  final damp = (ball ? c.ballDamp : c.discDamp) * b.dampMul, roll = ball ? c.ballRoll : c.discRoll;
  final ns = decaySpeed(sp, h, damp, roll);
  if (ns < c.vSleep) {
    b.vx = 0;
    b.vy = 0;
    return true;
  }
  final k = math.min(ns, c.vCap) / sp;
  b.vx *= k;
  b.vy *= k;
  return false;
}
