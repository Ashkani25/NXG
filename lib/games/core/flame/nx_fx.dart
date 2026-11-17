// Reusable Flame effects for NEXORA games (Flame F1): confetti / spark bursts, a small spark
// ring (pocket, hit), and a real animated fire effect (flickering particles that rise and cool
// from white-yellow to orange to deep red, additive blend) for power-shot trails and
// celebrations.
//
// Cheap on weak phones by design:
//  * a hard live-particle budget ([NxFxConfig.maxParticles]); requests beyond it are cut,
//  * fancyEffects off => ~40% of the particles and a smaller fire pool,
//  * reducedMotion => nothing is spawned at all,
//  * fire lives in a fixed, preallocated pool (typed arrays, colour look-up tables, one Paint),
//    so a running trail allocates nothing per frame; bursts allocate only when they are spawned.
// Effects are render-only: they never touch a game's deterministic simulation and use their own
// RNG.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/particles.dart';

/// Default confetti palette (NEXORA gold, pink, cyan, green, white).
const List<Color> kNxConfetti = <Color>[
  Color(0xFFFFD23A),
  Color(0xFFFF4A7A),
  Color(0xFF3BD0FF),
  Color(0xFF7BFF5A),
  Color(0xFFFFFFFF),
];

class NxFxConfig {
  const NxFxConfig({this.enabled = true, this.fancy = true});

  /// From the launch settings: reducedMotion turns every effect off, fancyEffects picks the budget.
  factory NxFxConfig.of({required bool fancyEffects, required bool reducedMotion}) =>
      NxFxConfig(enabled: !reducedMotion, fancy: fancyEffects && !reducedMotion);

  /// False with reducedMotion: nothing is spawned.
  final bool enabled;

  /// fancyEffects: full particle counts and the larger fire pool.
  final bool fancy;

  /// Hard cap of live particles (bursts + rings + fire) at any time.
  int get maxParticles => !enabled ? 0 : (fancy ? 220 : 72);

  /// Size of the preallocated fire pool.
  int get fireCapacity => !enabled ? 0 : (fancy ? 96 : 32);

  /// Multiplier applied to requested burst counts.
  double get countScale => fancy ? 1 : .4;

  /// Fire particles emitted per second by a full-strength trail.
  double get fireRate => fancy ? 120 : 45;
}

class NxFx extends Component {
  NxFx(this.config, {int seed = 7})
      : _rng = math.Random(seed),
        fire = NxFirePool(config.fireCapacity, math.Random(seed + 1), halo: config.fancy),
        super(priority: 100);

  final NxFxConfig config;
  final math.Random _rng;

  /// The fire particles (child component).
  final NxFirePool fire;

  // live burst bookkeeping: remaining seconds + particle count of each spawned system
  final List<double> _bLife = <double>[];
  final List<int> _bCount = <int>[];
  int _burstLive = 0;
  final Float64List _trailAcc = Float64List(4);

  /// Particles alive right now (bursts, rings and fire).
  int get live => _burstLive + fire.active;

  /// Particles still allowed before the cap.
  int get headroom => math.max(0, config.maxParticles - live);

  @override
  Future<void> onLoad() async {
    if (config.enabled) await add(fire);
  }

  /// How many of [requested] particles may be spawned now (scaled + capped).
  int admit(int requested) {
    if (!config.enabled || requested <= 0) return 0;
    final int scaled = math.max(1, (requested * config.countScale).round());
    return math.min(scaled, headroom);
  }

  void _track(int n, double life) {
    _bLife.add(life);
    _bCount.add(n);
    _burstLive += n;
  }

  /// Goal / win burst: confetti (spinning, flipping strips under gravity) or round sparks.
  /// Returns the number of particles spawned.
  int burst(Offset at,
      {int count = 36,
      double speed = 320,
      List<Color> colors = kNxConfetti,
      double life = 1.1,
      double gravity = 420,
      double size = 4,
      bool confetti = true}) {
    final int n = admit(count);
    if (n <= 0 || colors.isEmpty) return 0;
    final Paint paint = Paint();
    final List<List<Color>> fades = <List<Color>>[for (final Color c in colors) _fadeLut(c)];
    final Particle p = Particle.generate(
      count: n,
      lifespan: life,
      applyLifespanToChildren: false,
      generator: (int i) {
        final double a = _rng.nextDouble() * math.pi * 2;
        final double sp = speed * (.35 + .65 * _rng.nextDouble());
        final List<Color> lut = fades[i % fades.length];
        final double w = size * (.7 + .6 * _rng.nextDouble());
        final Rect rect = confetti ? Rect.fromCenter(center: Offset.zero, width: w * 1.7, height: w) : Rect.zero;
        final double rot0 = _rng.nextDouble() * math.pi, spin = (_rng.nextDouble() - .5) * 18;
        final double flip = 6 + _rng.nextDouble() * 10;
        final double pl = life * (.6 + .4 * _rng.nextDouble());
        return AcceleratedParticle(
          lifespan: pl,
          acceleration: Vector2(0, gravity),
          speed: Vector2(math.cos(a) * sp, math.sin(a) * sp - speed * .35),
          child: ComputedParticle(
            lifespan: pl,
            renderer: (Canvas c, Particle q) {
              final double t = q.progress;
              paint.color = lut[(t * (lut.length - 1)).round()];
              if (confetti) {
                final double el = t * pl;
                c.save();
                c.rotate(rot0 + spin * el);
                c.scale(1, math.cos(flip * el));
                c.drawRect(rect, paint);
                c.restore();
              } else {
                c.drawCircle(Offset.zero, w * .5 * (1 - .6 * t), paint);
              }
            },
          ),
        );
      },
    );
    add(ParticleSystemComponent(particle: p, position: Vector2(at.dx, at.dy)));
    _track(n, life);
    return n;
  }

  /// Small spark ring for a pocket / hard hit: evenly spaced sparks + one expanding ring.
  int ring(Offset at, Color color, {int count = 12, double radius = 26, double life = .42}) {
    final int n = admit(count + 1);
    if (n <= 0) return 0;
    final int sparks = math.max(0, n - 1);
    final Paint paint = Paint();
    final Paint stroke = Paint()
      ..style = PaintingStyle.stroke
      ..blendMode = BlendMode.plus;
    final List<Color> lut = _fadeLut(color);
    final double spd = radius / life * 1.6;
    final double off = _rng.nextDouble() * math.pi;
    final List<Particle> kids = <Particle>[
      ComputedParticle(
        lifespan: life,
        renderer: (Canvas c, Particle q) {
          final double t = q.progress;
          stroke
            ..color = lut[(t * (lut.length - 1)).round()]
            ..strokeWidth = 3 * (1 - t) + .5;
          c.drawCircle(Offset.zero, radius * (.35 + .9 * t), stroke);
        },
      ),
      for (int i = 0; i < sparks; i++)
        MovingParticle(
          lifespan: life,
          from: Vector2.zero(),
          to: Vector2(math.cos(off + i * 2 * math.pi / math.max(1, sparks)),
                  math.sin(off + i * 2 * math.pi / math.max(1, sparks))) *
              (spd * life),
          child: ComputedParticle(
            lifespan: life,
            renderer: (Canvas c, Particle q) {
              final double t = q.progress;
              paint.color = lut[(t * (lut.length - 1)).round()];
              c.drawCircle(Offset.zero, 2.4 * (1 - .7 * t), paint);
            },
          ),
        ),
    ];
    add(ParticleSystemComponent(
        particle: ComposedParticle(children: kids, lifespan: life), position: Vector2(at.dx, at.dy)));
    _track(n, life);
    return n;
  }

  /// A fire trail behind a fast body (screen px, px/s). [strength] 0..1 scales the rate and size.
  /// Call every frame while the body is fast; [slot] (0..3) keeps separate sources independent.
  int fireTrail(double x, double y, double vx, double vy, double strength, double dt,
      {int slot = 0, double size = 1}) {
    if (!config.enabled || dt <= 0) return 0;
    final int s = slot & 3;
    final double k = strength.clamp(0.0, 1.0).toDouble();
    _trailAcc[s] += config.fireRate * (.35 + .65 * k) * math.min(dt, .05);
    int n = 0;
    while (_trailAcc[s] >= 1) {
      _trailAcc[s] -= 1;
      if (headroom <= 0) {
        _trailAcc[s] = 0;
        break;
      }
      if (!fire.emit(x + (_rng.nextDouble() - .5) * 8 * size, y + (_rng.nextDouble() - .5) * 8 * size,
          -vx * .12 + (_rng.nextDouble() - .5) * 50, -vy * .12 + (_rng.nextDouble() - .5) * 50 - 60,
          .3 + .25 * _rng.nextDouble() * (.5 + k), (6 + 6 * k) * size * (.7 + .5 * _rng.nextDouble()))) {
        break;
      }
      n++;
    }
    return n;
  }

  /// A celebration flame: a short fountain of fire rising from [at].
  int fireBurst(Offset at, {int count = 40, double size = 1.4}) {
    final int n = math.min(admit(count), fire.capacity - fire.active);
    int made = 0;
    for (int i = 0; i < n; i++) {
      final double a = -math.pi / 2 + (_rng.nextDouble() - .5) * 2.2;
      final double sp = 120 + 260 * _rng.nextDouble();
      if (!fire.emit(at.dx + (_rng.nextDouble() - .5) * 60 * size, at.dy + (_rng.nextDouble() - .5) * 16,
          math.cos(a) * sp, math.sin(a) * sp, .45 + .5 * _rng.nextDouble(), (6 + 5 * _rng.nextDouble()) * size)) {
        break;
      }
      made++;
    }
    return made;
  }

  /// Bookkeeping only (Flame updates the children); public so tests can step it without a game.
  void tickBudget(double dt) {
    for (int i = _bLife.length - 1; i >= 0; i--) {
      _bLife[i] -= dt;
      if (_bLife[i] <= 0) {
        _burstLive -= _bCount[i];
        _bLife.removeAt(i);
        _bCount.removeAt(i);
      }
    }
  }

  @override
  void update(double dt) {
    tickBudget(dt);
  }

  static List<Color> _fadeLut(Color c) => List<Color>.generate(
      9, (int i) => c.withValues(alpha: c.a * (1 - math.pow(i / 8, 2).toDouble())), growable: false);
}

/// Fixed-size pool of fire particles: rise, flicker, shrink and cool (white-yellow -> orange ->
/// red -> gone), additive blend. Drawn in ONE drawRawAtlas call from a soft radial sprite with
/// per-particle colours; all buffers are preallocated, so a running fire allocates nothing.
class NxFirePool extends Component {
  NxFirePool(this.capacity, this._rng, {this.halo = true})
      : _x = Float32List(capacity),
        _y = Float32List(capacity),
        _vx = Float32List(capacity),
        _vy = Float32List(capacity),
        _age = Float32List(capacity),
        _life = Float32List(capacity),
        _size = Float32List(capacity),
        _ph = Float32List(capacity),
        _xf = Float32List(capacity * 2 * 4),
        _rects = Float32List(capacity * 2 * 4),
        _cols = Int32List(capacity * 2),
        super(priority: 50) {
    for (int i = 0; i < capacity * 2; i++) {
      _rects[i * 4 + 2] = _spr;
      _rects[i * 4 + 3] = _spr;
    }
  }

  final int capacity;
  final bool halo;
  final math.Random _rng;
  final Float32List _x, _y, _vx, _vy, _age, _life, _size, _ph;
  final Float32List _xf, _rects;
  final Int32List _cols;
  int _n = 0;

  /// Upward buoyancy (px/s^2, negative y is up on screen).
  static const double rise = 260;

  /// Live particles.
  int get active => _n;

  static const double _spr = 64;
  static Image? _sprite;

  /// Soft white radial blob, built once per process.
  static Image _spriteImage() {
    final Image? have = _sprite;
    if (have != null) return have;
    final PictureRecorder rec = PictureRecorder();
    final Canvas c = Canvas(rec);
    const Offset ctr = Offset(_spr / 2, _spr / 2);
    c.drawCircle(
        ctr,
        _spr / 2,
        Paint()
          ..shader = Gradient.radial(ctr, _spr / 2, const <Color>[
            Color(0xFFFFFFFF),
            Color(0x99FFFFFF),
            Color(0x26FFFFFF),
            Color(0x00FFFFFF),
          ], const <double>[0, .32, .66, 1]));
    final Image img = rec.endRecording().toImageSync(_spr.toInt(), _spr.toInt());
    _sprite = img;
    return img;
  }

  static final Int32List _core = _ramp(<Color>[
    const Color(0xFFFFF4C8),
    const Color(0xFFFFD84A),
    const Color(0xFFFF9A1E),
    const Color(0xFFFF4E10),
    const Color(0xFF9A1A06),
  ], <double>[.85, .8, .7, .45, 0]);
  static final Int32List _glow = Int32List.fromList(<int>[
    for (final int c in _core)
      Color(c).withValues(alpha: Color(c).a * .28).toARGB32()
  ]);
  final Paint _paint = Paint()
    ..blendMode = BlendMode.plus
    ..filterQuality = FilterQuality.low;

  static Int32List _ramp(List<Color> stops, List<double> alpha) {
    const int n = 16;
    return Int32List.fromList(List<int>.generate(n, (int i) {
      final double t = i / (n - 1) * (stops.length - 1);
      final int a = t.floor().clamp(0, stops.length - 2);
      final double f = t - a;
      final Color c = Color.lerp(stops[a], stops[a + 1], f)!;
      final double al = alpha[a] + (alpha[a + 1] - alpha[a]) * f;
      return c.withValues(alpha: al.clamp(0.0, 1.0).toDouble()).toARGB32();
    }));
  }

  /// Adds one particle; false when the pool is full.
  bool emit(double x, double y, double vx, double vy, double life, double size) {
    if (_n >= capacity || life <= 0) return false;
    final int i = _n++;
    _x[i] = x;
    _y[i] = y;
    _vx[i] = vx;
    _vy[i] = vy;
    _age[i] = 0;
    _life[i] = life;
    _size[i] = size;
    _ph[i] = _rng.nextDouble() * 6.283;
    return true;
  }

  @override
  void update(double dt) {
    if (_n == 0) return;
    final double d = math.min(dt, .05);
    final double drag = math.pow(.18, d).toDouble();
    int i = 0;
    while (i < _n) {
      _age[i] += d;
      if (_age[i] >= _life[i]) {
        final int j = --_n; // swap-remove
        _x[i] = _x[j];
        _y[i] = _y[j];
        _vx[i] = _vx[j];
        _vy[i] = _vy[j];
        _age[i] = _age[j];
        _life[i] = _life[j];
        _size[i] = _size[j];
        _ph[i] = _ph[j];
        continue;
      }
      _vy[i] -= rise * d;
      _vx[i] *= drag;
      _vy[i] = _vy[i] * (.5 + .5 * drag);
      _x[i] += _vx[i] * d + math.sin(_ph[i] + _age[i] * 17) * 14 * d; // lick sideways
      _y[i] += _vy[i] * d;
      i++;
    }
  }

  void _put(int k, double x, double y, double radius, int color) {
    final double sc = radius * 2 / _spr;
    final int o = k * 4;
    _xf[o] = sc;
    _xf[o + 1] = 0;
    _xf[o + 2] = x - _spr / 2 * sc;
    _xf[o + 3] = y - _spr / 2 * sc;
    _cols[k] = color;
  }

  @override
  void render(Canvas canvas) {
    if (_n == 0) return;
    int k = 0;
    for (int i = 0; i < _n; i++) {
      final double t = _age[i] / _life[i];
      final int ci = (t * (_core.length - 1)).round();
      final double flick = .8 + .2 * math.sin(_ph[i] + _age[i] * 31);
      final double r = _size[i] * (1.15 - .6 * t) * flick;
      if (halo) _put(k++, _x[i], _y[i], r * 2.3, _glow[ci]);
      _put(k++, _x[i], _y[i], r * 1.35, _core[ci]);
    }
    canvas.drawRawAtlas(_spriteImage(), Float32List.sublistView(_xf, 0, k * 4),
        Float32List.sublistView(_rects, 0, k * 4), Int32List.sublistView(_cols, 0, k), BlendMode.modulate,
        null, _paint);
  }
}
