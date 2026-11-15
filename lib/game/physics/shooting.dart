// Drag -> shot. The pull length (past the 18 px dead zone, capped at LMAX) gives the pull fraction p in 0..1;
// the launch speed is
//     v = shotBase * c(p) * powerMul(power),   c(p) = shotMin + (1 - shotMin) * p^shotGamma,   v <= vCap
// c is smooth, monotonic and gently eased (gamma 1.5): a short pull is a soft, controllable touch, half a pull ~39%,
// a full pull 100%. powerMul maps the piece's power stat 1..10 linearly onto 0.70 .. 1.30, so every power step
// changes the launch speed by ~6.7% of the base (clearly different glide distances, see PHYSICS_NOTES.md).
import '../fdlibm.dart';
import 'body.dart';
import 'physics_config.dart';

/// pull fraction 0..1 -> share of the full-pull speed
double shotCurveN(double p, [PhysicsConfig c = kPhys]) {
  final q = p < 0 ? 0.0 : (p > 1 ? 1.0 : p);
  if (q == 0) return c.shotMin;
  return c.shotMin + (1 - c.shotMin) * fpow(q, c.shotGamma); // fdlibm pow: bit-identical on every peer
}

/// launch speed for pull fraction [p] and power stat [power] (1..10)
double launchSpeed(double p, double power, [PhysicsConfig c = kPhys]) {
  final v = c.shotBase * shotCurveN(p, c) * c.powerMul(power);
  return v > c.vCap ? c.vCap : v;
}

/// apply the piece attributes to a disc body (mass, power factor, damping, rail grip)
void applyAttrs(Body b, PieceAttrs a, [PhysicsConfig c = kPhys]) {
  b.attrs = a;
  b.im = 1 / c.massOf(a.mass);
  b.pf = c.powerFactor(a.power);
  b.dampMul = statLerp(a.control, c.controlLo, c.controlHi);
  b.muMul = statLerp(a.inertia, c.inertiaLo, c.inertiaHi);
}

/// put a disc in motion along the unit direction (ux, uy)
void launch(Body b, double ux, double uy, double v) {
  b.vx = ux * v;
  b.vy = uy * v;
  b.gout = null;
}
