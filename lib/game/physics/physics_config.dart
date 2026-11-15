// NEXORA physics v0.6.4 ('stars' profile): every gameplay tunable of the unified physics world lives here.
//
// Units: world px (play area ~830 x 1424 on the default pitch), px/s, px/s^2, 1/s, seconds.
// Measured effects of these values: PHYSICS_NOTES.md (tool/snap/sweep_v064_test.dart regenerates the tables).
import 'dart:math' as math;

/// Linear map of a 1..10 stat onto [lo, hi] (1 -> lo, 10 -> hi), clamped.
double statLerp(double s, double lo, double hi) {
  final q = s.isNaN ? 0.5 : ((s < 1 ? 1 : (s > 10 ? 10 : s)) - 1) / 9;
  return lo + (hi - lo) * q;
}

/// Physical attributes of one piece (disc). All 1..10; 5.5 is neutral (x1.0) for every attribute but power.
class PieceAttrs {
  /// shot launch speed (statLerp 0.70 .. 1.30 of the base speed) and a small bonus to the impulse it strikes with
  final double power;

  /// mass (independent of power): 0.80 .. 1.25 x the base disc mass
  final double mass;

  /// collision strength: restitution bonus when this piece is the striker (-0.04 .. +0.04)
  final double strength;

  /// impact resistance: restitution reduction when this piece is struck (+0.03 .. -0.03), i.e. it absorbs more
  final double resist;

  /// control / friction: linear damping x 0.92 .. 1.08 (higher = shorter, more controllable glide)
  final double control;

  /// rotational inertia: tangential (rail / contact) friction x 1.15 .. 0.85 (heavier spin = less grip loss)
  final double inertia;

  const PieceAttrs({this.power = 5, this.mass = 5.5, this.strength = 5.5, this.resist = 5.5, this.control = 5.5, this.inertia = 5.5});
  static const neutral = PieceAttrs(power: 5.5);
}

class PhysicsConfig {
  // ---- integration ----
  final double step; // fixed physics step (s); render rate never changes it
  final double subPx; // max travel of the fastest body per substep (px)
  final int subMax; // substep cap per step
  final int maxEvents; // CCD contact events resolved per substep
  final int posIters; // positional-correction passes per substep
  final int stepCap; // physics steps per rendered frame (backlog beyond is dropped)

  // ---- bodies ----
  final double discR, ballR, postR, cornerR;
  final double discMass, ballMass;
  final double massLo, massHi; // mass stat range (x discMass)

  // ---- friction: dv/dt = -roll - damp * v (exact flow per substep), sleep below vSleep ----
  final double discDamp, discRoll, ballDamp, ballRoll;
  final double controlLo, controlHi; // control stat -> damping multiplier
  final double vSleep;
  final double vCap; // hard speed cap for every body (no runaway, ever)

  // ---- shot ----
  final double shotBase; // launch speed at full pull, power multiplier 1.0
  final double shotMin, shotGamma; // curve c(p) = shotMin + (1 - shotMin) * p^shotGamma
  final double powerLo, powerHi; // power stat -> launch multiplier
  final double vipMul; // legacy cfg without stats: VIP shooter multiplier

  // ---- body-body contacts ----
  final double eDiscDisc, eDiscBall;
  final double vRest; // approach speed below which a contact is perfectly inelastic (no micro-bounces)
  final double muContact; // tangential (Coulomb) friction between bodies
  final double strengthE, resistE, powerHitE; // attribute restitution modifiers (see PieceAttrs)
  final double eMin, eMax;
  final double slop, posPercent; // positional correction

  // ---- boundaries (rails, corner arcs, posts, goal nets) ----
  final double eRailDisc, eRailBall, ePost, eNet;
  final double eCorner, muCornerK; // rounded corner cushion: softer normal, less grip (bodies slide round and out)
  final double bankAcc, bankZone; // corner bank: within bankZone px of the corner arc a body is eased back into play
  final double muRail; // tangential Coulomb friction on a rail / post
  final double inertiaLo, inertiaHi; // inertia stat -> muRail multiplier
  final double boostK; // impact boost: extra normal speed = boostK * powerFactor * cos(incidence) * |vn|
  final double keepMax; // outgoing speed <= keepMax x incoming speed (boost can never add energy)
  final double eGoalHold; // ball inside the net after a goal (phase goal): soft net

  // ---- goals ----
  final double goalHalfW, goalDepth;
  final double ejectSpeed, ejectBelow; // a slow disc inside a goal is walked back out (rule)

  const PhysicsConfig({
    required this.step,
    required this.subPx,
    required this.subMax,
    required this.maxEvents,
    required this.posIters,
    required this.stepCap,
    required this.discR,
    required this.ballR,
    required this.postR,
    required this.cornerR,
    required this.discMass,
    required this.ballMass,
    required this.massLo,
    required this.massHi,
    required this.discDamp,
    required this.discRoll,
    required this.ballDamp,
    required this.ballRoll,
    required this.controlLo,
    required this.controlHi,
    required this.vSleep,
    required this.vCap,
    required this.shotBase,
    required this.shotMin,
    required this.shotGamma,
    required this.powerLo,
    required this.powerHi,
    required this.vipMul,
    required this.eDiscDisc,
    required this.eDiscBall,
    required this.vRest,
    required this.muContact,
    required this.strengthE,
    required this.resistE,
    required this.powerHitE,
    required this.eMin,
    required this.eMax,
    required this.slop,
    required this.posPercent,
    required this.eRailDisc,
    required this.eRailBall,
    required this.ePost,
    required this.eNet,
    required this.eCorner,
    required this.muCornerK,
    required this.bankAcc,
    required this.bankZone,
    required this.muRail,
    required this.inertiaLo,
    required this.inertiaHi,
    required this.boostK,
    required this.keepMax,
    required this.eGoalHold,
    required this.goalHalfW,
    required this.goalDepth,
    required this.ejectSpeed,
    required this.ejectBelow,
  });

  double powerMul(double power) => statLerp(power, powerLo, powerHi);

  /// power factor used by the impact boost and the striking bonus: 0.70 .. 1.30 (same scale as the launch multiplier)
  double powerFactor(double power) => statLerp(power, powerLo, powerHi);

  double massOf(double massStat) => discMass * statLerp(massStat, massLo, massHi);

  /// glide distance (px) and time (s) to rest from speed v with damping k and rolling decel f (no walls)
  static (double, double) glide(double v, double k, double f) {
    final t = math.log(1 + k * v / f) / k;
    return (v / k - f / (k * k) * math.log(1 + k * v / f), t);
  }
}

/// v0.6.4 values. Reasoning per group in PHYSICS_NOTES.md.
const kPhys = PhysicsConfig(
  step: 1 / 240, subPx: 4, subMax: 16, maxEvents: 12, posIters: 3, stepCap: 14,
  // sizes: discs unchanged (49); ball 21.6 -> 24.2 (+12%, owner); posts drawn and collided at the same radius
  discR: 49, ballR: 24.2, postR: 9, cornerR: 80,
  discMass: 3, ballMass: 1, massLo: .8, massHi: 1.25,
  // glide: disc full shot (3510 px/s) ~1.55 k px / 1.7 s, weak (25%) ~0.2 k px / 0.9 s; ball a little freer
  discDamp: 2.0, discRoll: 220, ballDamp: 1.6, ballRoll: 165,
  controlLo: .92, controlHi: 1.08,
  vSleep: 5, vCap: 3800,
  shotBase: 2700, shotMin: .06, shotGamma: 1.5, powerLo: .70, powerHi: 1.30, vipMul: 1.16,
  eDiscDisc: .80, eDiscBall: .88, vRest: 15, muContact: .04,
  strengthE: .04, resistE: .03, powerHitE: .05, eMin: .55, eMax: .95,
  slop: .3, posPercent: .8,
  eRailDisc: .60, eRailBall: .64, ePost: .62, eNet: .35, muRail: .08,
  eCorner: .55, muCornerK: .5, bankAcc: 900, bankZone: 10, inertiaLo: 1.15, inertiaHi: .85,
  boostK: .10, keepMax: .95, eGoalHold: .2,
  goalHalfW: 136, goalDepth: 74, ejectSpeed: 343, ejectBelow: 190,
);
