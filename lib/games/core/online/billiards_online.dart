/// Online 8-ball billiards board (host-authoritative, wire format in billiards_online_sync.dart).
///
///  * my turn: aim / ball-in-hand / spin / power exactly like offline; my device simulates the
///    shot with the offline engine and submits the final table via `gm_shot`;
///  * opponent / spectator: the shot is replayed from the submitted `prev` table with the same
///    deterministic physics for the animation, then the view snaps to the submitted table;
///  * the server owns the 45 s clock (top bar). An idle timeout passes the turn with ball in hand.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexora/core/assets/app_assets.dart';
import 'package:nexora/core/settings/app_settings.dart';
import 'package:nexora/core/theme/nx_theme.dart';
import 'package:nexora/games/billiards/core/pool_config.dart';
import 'package:nexora/games/billiards/core/pool_match.dart';
import 'package:nexora/games/billiards/core/pool_physics.dart';
import 'package:nexora/games/billiards/ui/pool_hud.dart';
import 'package:nexora/games/billiards/ui/pool_painter.dart';
import 'package:nexora/games/billiards/ui/pool_scene.dart';

import 'billiards_online_sync.dart';
import 'gm_match_controller.dart';
import 'gm_models.dart';

/// Online board for a live billiards match.
Widget buildBilliardsOnline(GmMatchController c) => BilliardsOnlineBoard(c: c);

/// Extra line on the result card.
String? billiardsOnlineResultDetail(BuildContext context, GmView v) {
  final PoolMatch m = BilliardsOnlineSync.derive(v);
  if (v.reason == 'eight_early') return context.tx('توپ ۸ زودتر از موعد افتاد', '8-ball potted too early');
  if (v.reason == 'eight_foul') return context.tx('توپ ۸ با خطا افتاد', '8-ball potted on a foul');
  return '${v.nameOf(0)} ${m.pottedCount(0)} – ${m.pottedCount(1)} ${v.nameOf(1)}';
}

enum _Stage { aiming, striking, rolling, over }

class BilliardsOnlineBoard extends StatefulWidget {
  const BilliardsOnlineBoard({super.key, required this.c});
  final GmMatchController c;

  @override
  State<BilliardsOnlineBoard> createState() => _BilliardsOnlineBoardState();
}

class _BilliardsOnlineBoardState extends State<BilliardsOnlineBoard> with SingleTickerProviderStateMixin {
  static const Color _p0Color = NxColors.turquoise;
  static const Color _p1Color = NxColors.pink;

  late PoolMatch _match;
  late final PoolScene _scene;
  late final Ticker _ticker;
  final math.Random _rng = math.Random(7);
  StreamSubscription<GmView>? _sub;
  Duration _last = Duration.zero;
  double _acc = 0;

  _Stage _stage = _Stage.aiming;
  PoolShot? _pending;
  double _strikeT = 0;

  double _power = 0;
  double _chargeStartX = 0;
  bool _charging = false;
  bool _draggingCue = false;
  double _spin = 0;
  double _side = 0;
  bool _spinOpen = false;

  String _bannerText = '';
  Color _bannerColor = NxColors.iceWhite;
  int _bannerId = 0;
  double _bannerLeft = 0;

  // sync
  int _appliedVersion = -1;
  int _appliedShots = -1;
  bool _replaying = false;
  bool _submitting = false;
  bool _dead = false;
  GmView? _pendingView;
  GmView? _replayTarget;
  PoolMatch? _prev;
  PoolShot? _shotRec;

  bool _fa = true;
  bool _fancy = true;
  bool _reduced = false;
  bool _haptics = true;
  bool _ready = false;
  bool _inDeps = false;
  int _lastHapticMs = 0;
  double _s = 1;

  GmMatchController get c => widget.c;
  String _tx(String fa, String en) => _fa ? fa : en;

  @override
  void initState() {
    super.initState();
    _match = PoolMatch.newRack();
    _scene = PoolScene(_match, cueSkin: 'cue_classic', fancy: true);
    _hook(_match);
    _scene.syncLast();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _fa = context.isFa;
    if (_ready) return;
    _ready = true;
    _reduced = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    try {
      final AppSettings s = ProviderScope.containerOf(context, listen: false).read(settingsProvider);
      _fancy = s.fancyEffects;
      _reduced = s.reducedMotion;
      _haptics = s.haptics;
    } catch (_) {/* no ProviderScope (tests): defaults */}
    final GmView? v = c.view;
    _inDeps = true;
    if (v != null) _onView(v);
    _inDeps = false;
    _sub = c.views.listen(_onView);
  }

  @override
  void dispose() {
    _dead = true;
    _sub?.cancel();
    _ticker.dispose();
    _match.world.onImpact = null;
    _match.world.onPocket = null;
    _scene.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- sync
  void _hook(PoolMatch m) {
    m.world.onImpact = _onImpact;
    m.world.onPocket = _onPocket;
  }

  void _setMatch(PoolMatch m) {
    _match.world.onImpact = null;
    _match.world.onPocket = null;
    _match = m;
    _scene.match = m;
    _hook(m);
    _scene.syncLast();
  }

  int? get _mySeat => c.view?.mySeat;

  bool get _canAct {
    final GmView? v = c.view;
    if (v == null || !v.myTurn || _replaying || _submitting || _spinOpen) return false;
    if (_appliedVersion != v.version) return false;
    return _stage == _Stage.aiming && !_match.isOver && _match.current == v.mySeat;
  }

  void _onView(GmView v) {
    if (_dead) return;
    if (_appliedVersion >= 0 && v.version <= _appliedVersion) return;
    if (_stage == _Stage.striking || _stage == _Stage.rolling || _submitting) {
      _pendingView = v;
      return;
    }
    if (BilliardsOnlineSync.shouldReplay(v, _appliedShots)) {
      final PoolMatch? prev = billiardsMatchFromJson(v.state['prev']);
      final PoolShot? shot = billiardsShotFromJson(v.state['shot']);
      if (prev != null && shot != null && prev.validate(shot) == null) {
        _setMatch(prev);
        _appliedVersion = v.version;
        _appliedShots = BilliardsOnlineSync.shotsOf(v);
        _replayTarget = v;
        _replaying = true;
        _scene.aimAngle = math.atan2(shot.dirY, shot.dirX);
        _stage = _Stage.aiming;
        _scene.cueOpacity = 1;
        _shoot(shot, replay: true);
        return;
      }
    }
    _apply(v);
  }

  void _apply(GmView v) {
    final int before = _appliedShots;
    _setMatch(BilliardsOnlineSync.derive(v));
    _appliedVersion = v.version;
    _appliedShots = BilliardsOnlineSync.shotsOf(v);
    _replaying = false;
    _replayTarget = null;
    _stage = _match.isOver || !v.live ? _Stage.over : _Stage.aiming;
    final Map<String, dynamic> foul = gmMap(v.state['foul']);
    if (before >= 0 && _appliedShots == before && foul['reason'] == 'timeout' && v.live) {
      final int s = gmInt(foul['seat'], -1);
      _banner(
          s == v.mySeat
              ? _tx('وقتت تمام شد — توپ در دست حریف', 'Time up — ball in hand for your opponent')
              : _tx('وقت حریف تمام شد — توپ در دست توست', 'Opponent timed out — ball in hand'),
          NxColors.danger);
    } else if (before < 0 && v.live) {
      _banner(_tx('بریک: ${v.nameOf(_match.current)}', 'Break: ${v.nameOf(_match.current)}'),
          _match.current == 0 ? _p0Color : _p1Color);
    }
    _prepareTurn();
    if (mounted && !_inDeps) setState(() {});
    // a table that ended without a reported finish: the current shooter closes it
    if (v.live && v.myTurn && _match.isOver) {
      final Map<String, dynamic>? fin = BilliardsOnlineSync.finishOf(_match);
      if (fin != null) {
        _submitting = true;
        c
            .shot(<String, dynamic>{
              if (v.state['seed'] != null) 'seed': v.state['seed'],
              'board': billiardsMatchToJson(_match),
              'scores': BilliardsOnlineSync.scoresOf(_match),
            }, _match.current, finish: fin)
            .whenComplete(_afterSubmit);
      }
    }
  }

  Future<void> _submit() async {
    final PoolMatch? prev = _prev;
    final PoolShot? shot = _shotRec;
    final GmView? v = c.view;
    if (prev == null || shot == null || v == null) return;
    _submitting = true;
    if (mounted) setState(() {});
    final Map<String, dynamic> state = BilliardsOnlineSync.encode(
      prev: prev,
      shot: shot,
      after: _match,
      shooter: prev.current,
      seed: v.state['seed'],
    );
    final Map<String, dynamic>? fin = BilliardsOnlineSync.finishOf(_match);
    final int next = BilliardsOnlineSync.nextTurn(_match);
    final int version = v.version;
    bool ok = await c.shot(state, next, finish: fin);
    if (!ok && !_dead) {
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      final GmView? cur = c.view;
      if (!_dead && cur != null && cur.version == version && cur.myTurn) {
        ok = await c.shot(state, next, finish: fin);
      }
    }
    _prev = null;
    _shotRec = null;
    if (!ok) _appliedVersion = -1;
    _afterSubmit();
  }

  void _afterSubmit() {
    _submitting = false;
    if (_dead) return;
    final GmView? pending = _pendingView;
    _pendingView = null;
    if (pending != null) _onView(pending);
    final GmView? latest = c.view;
    if (latest != null && (_appliedVersion < 0 || latest.version > _appliedVersion)) _onView(latest);
    if (mounted) setState(() {});
  }

  // ---------------------------------------------------------------- helpers
  void _haptic(int level) {
    if (!_haptics) return;
    final int now = DateTime.now().millisecondsSinceEpoch;
    if (level == 0 && now - _lastHapticMs < 90) return;
    _lastHapticMs = now;
    if (level == 0) {
      HapticFeedback.selectionClick();
    } else if (level == 1) {
      HapticFeedback.lightImpact();
    } else {
      HapticFeedback.mediumImpact();
    }
  }

  void _onImpact(double x, double y, double strength, bool cushion) {
    if (strength < 140 || !_fancy || _reduced) return;
    _scene.spark(x, y, strength, cushion ? NxColors.gold : NxColors.iceWhite, _rng);
    _haptic(0);
  }

  void _onPocket(int id, int pocket) {
    _scene.flashes.add(PoolFlash(pocket, id == 0 ? NxColors.danger : (id == 8 ? NxColors.violet : NxColors.electricBlue)));
    _scene.sinks.add(PoolSink(id, PoolConfig.pockets[pocket][0], PoolConfig.pockets[pocket][1]));
    _haptic(1);
  }

  void _banner(String text, Color color, {double seconds = 2.2}) {
    _bannerText = text;
    _bannerColor = color;
    _bannerId++;
    _bannerLeft = seconds;
  }

  String _name(int seat) {
    final GmView? v = c.view;
    final String n = v?.nameOf(seat) ?? '…';
    return _mySeat == seat ? '$n ${_tx('(تو)', '(you)')}' : n;
  }

  void _syncScene() {
    final bool aiming = _stage == _Stage.aiming && !_match.isOver;
    _scene.ballInHand = _match.ballInHand && aiming && _canAct;
    _scene.kitchenOnly = _match.kitchenOnly;
    _scene.showAim = aiming && _canAct;
    _scene.showCue = (aiming && _canAct) || _stage == _Stage.striking || (_stage == _Stage.rolling && _scene.cueOpacity > 0);
  }

  void _setAimTowardNearestLegal() {
    final PoolBall cue = _match.cue;
    double best = double.infinity;
    for (final int id in _match.legalTargets()) {
      final PoolBall b = _match.balls[id];
      final double dx = b.x - cue.x, dy = b.y - cue.y;
      final double d = dx * dx + dy * dy;
      if (d < best) {
        best = d;
        _scene.aimAngle = math.atan2(dy, dx);
      }
    }
  }

  void _prepareTurn() {
    _scene.pull = 0;
    _scene.strikeOffset = 0;
    _scene.cueOpacity = 1;
    _power = 0;
    _spin = 0;
    _side = 0;
    _draggingCue = false;
    _scene.placing = false;
    _setAimTowardNearestLegal();
    _syncScene();
  }

  // ---------------------------------------------------------------- loop
  void _onTick(Duration elapsed) {
    double dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (dt > 0.05) dt = 0.05;
    if (dt < 0) dt = 0;
    if (_bannerLeft > 0) {
      _bannerLeft -= dt;
      if (_bannerLeft <= 0 && mounted) setState(() {});
    }
    switch (_stage) {
      case _Stage.aiming:
      case _Stage.over:
        break;
      case _Stage.striking:
        _strikeT += dt / 0.11;
        final double travel = 6 + _scene.pull * 110;
        _scene.strikeOffset = travel * _strikeT.clamp(0.0, 1.0).toDouble();
        if (_strikeT >= 1) _launchPending();
        break;
      case _Stage.rolling:
        _scene.cueOpacity = math.max(0.0, _scene.cueOpacity - dt * 3.5);
        if (_scene.cueOpacity <= 0) _scene.showCue = false;
        _acc += dt;
        while (_acc >= PoolConfig.dt) {
          _acc -= PoolConfig.dt;
          if (_match.world.tick()) {
            _onShotDone();
            break;
          }
        }
        break;
    }
    _scene.updateRoll();
    _scene.advanceFx(dt);
    _scene.repaint();
  }

  void _shoot(PoolShot shot, {bool replay = false}) {
    if (_match.validate(shot) != null) return;
    if (!replay) {
      if (!_canAct) return;
      _prev = _match.clone();
      _shotRec = shot;
    }
    _pending = shot;
    _strikeT = 0;
    _stage = _Stage.striking;
    _scene.pull = shot.power;
    _scene.showCue = true;
    _scene.showAim = false;
    _scene.ballInHand = false;
    if (mounted) setState(() {});
  }

  void _launchPending() {
    final PoolShot? shot = _pending;
    _pending = null;
    if (shot == null || !_match.beginShot(shot)) {
      // cannot happen for a validated shot; resync to the server's table
      _stage = _Stage.aiming;
      _replaying = false;
      _prev = null;
      _shotRec = null;
      _appliedVersion = -1;
      final GmView? v = c.view;
      if (v != null) _onView(v);
      return;
    }
    _haptic(2);
    if (_scene.fancy && _fancy && !_reduced) {
      final PoolBall cue = _match.cue;
      _scene.spark(cue.x - math.cos(_scene.aimAngle) * PoolConfig.ballR, cue.y - math.sin(_scene.aimAngle) * PoolConfig.ballR,
          shot.power * 2600, NxColors.electricBlue, _rng);
    }
    _acc = 0;
    _stage = _Stage.rolling;
    if (mounted) setState(() {});
  }

  void _onShotDone() {
    final PoolShotReport r = _match.finishShot();
    _scene.syncLast();
    _stage = _match.isOver ? _Stage.over : _Stage.aiming;
    _announce(r);
    if (_replaying) {
      _replaying = false;
      final GmView? t = _replayTarget;
      _replayTarget = null;
      final GmView? next = _pendingView;
      _pendingView = null;
      if (t != null) {
        final int want = gmInt(t.state['hash']);
        if (want != 0 && want != _match.stateHash) {
          debugPrint('billiards online: replay hash mismatch ${_match.stateHash} != $want (snapping)');
        }
        _apply(t);
      }
      if (next != null) _onView(next);
    } else if (_prev != null) {
      _prepareTurn();
      unawaited(_submit());
    } else {
      _prepareTurn();
    }
    if (mounted) setState(() {});
  }

  void _announce(PoolShotReport r) {
    if (_match.isOver) {
      final int w = _match.winner ?? 0;
      String text;
      switch (_match.endReason) {
        case PoolEndReason.eightPotted:
          text = _tx('${_name(w)} توپ ۸ را انداخت و برنده شد!', '${_name(w)} sinks the 8 and wins!');
          break;
        case PoolEndReason.eightEarly:
          text = _tx('توپ ۸ زودتر افتاد — ${_name(w)} برنده شد', '8-ball potted early — ${_name(w)} wins');
          break;
        case PoolEndReason.eightWithFoul:
          text = _tx('توپ ۸ با خطا افتاد — ${_name(w)} برنده شد', '8-ball potted on a foul — ${_name(w)} wins');
          break;
        case PoolEndReason.none:
          text = _tx('${_name(w)} برنده شد', '${_name(w)} wins');
          break;
      }
      _banner(text, w == 0 ? _p0Color : _p1Color, seconds: 3);
      return;
    }
    final String next = _name(_match.current);
    final Color nextColor = _match.current == 0 ? _p0Color : _p1Color;
    if (r.isFoul) {
      String f;
      switch (r.foul) {
        case PoolFoul.scratch:
          f = _tx('خطا: توپ سفید افتاد', 'Foul: scratch');
          break;
        case PoolFoul.noContact:
          f = _tx('خطا: به هیچ توپی نخورد', 'Foul: no ball hit');
          break;
        case PoolFoul.wrongBallFirst:
          f = _tx('خطا: اول به توپ اشتباه خورد', 'Foul: wrong ball first');
          break;
        case PoolFoul.noRail:
          f = _tx('خطا: بعد از برخورد هیچ توپی به دیواره نخورد', 'Foul: no rail after contact');
          break;
        case PoolFoul.none:
          f = '';
          break;
      }
      _banner('$f\n${_tx('توپ در دست: $next', 'Ball in hand: $next')}', NxColors.danger, seconds: 2.6);
    } else if (r.assigned != PoolGroup.none) {
      final bool solids = r.assigned == PoolGroup.solids;
      _banner(
          _tx('${_name(r.shooter)}: ${solids ? 'ساده‌ها (۱ تا ۷)' : 'راه‌راه‌ها (۹ تا ۱۵)'}',
              '${_name(r.shooter)}: ${solids ? 'solids (1-7)' : 'stripes (9-15)'}'),
          r.shooter == 0 ? _p0Color : _p1Color);
    } else if (r.eightRespotted) {
      _banner(_tx('توپ ۸ در بریک افتاد و برگشت', '8-ball potted on the break — re-spotted'), NxColors.violet);
    } else if (r.continues) {
      _banner(_tx('عالی! دوباره ${r.shooter == _mySeat ? 'بزن' : 'می‌زند'}', r.shooter == _mySeat ? 'Nice! Shoot again' : '$next shoots again'),
          nextColor,
          seconds: 1.4);
    } else {
      _banner(_tx('نوبت $next', "$next's turn"), nextColor, seconds: 1.5);
    }
  }

  // ---------------------------------------------------------------- input
  Offset _toTable(Offset local) => Offset(local.dx / _s - PoolConfig.artClothLeft, local.dy / _s - PoolConfig.artClothTop);

  void _aimAt(Offset t) {
    final PoolBall cue = _match.cue;
    final double dx = t.dx - cue.x, dy = t.dy - cue.y;
    if (dx * dx + dy * dy < 16) return;
    _scene.aimAngle = math.atan2(dy, dx);
  }

  void _onPanStart(DragStartDetails d) {
    if (!_canAct) return;
    final Offset t = _toTable(d.localPosition);
    final PoolBall cue = _match.cue;
    final double dx = t.dx - cue.x, dy = t.dy - cue.y;
    if (_match.ballInHand && dx * dx + dy * dy < (PoolConfig.ballR * 3.2) * (PoolConfig.ballR * 3.2)) {
      _draggingCue = true;
      _scene.placing = true;
      return;
    }
    _aimAt(t);
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (!_canAct) return;
    final Offset t = _toTable(d.localPosition);
    if (_draggingCue) {
      const double r = PoolConfig.ballR;
      final double x = t.dx.clamp(r, PoolConfig.tableW - r).toDouble();
      double y = t.dy.clamp(r, PoolConfig.tableH - r).toDouble();
      if (_match.kitchenOnly && y < PoolConfig.headStringY) y = PoolConfig.headStringY;
      _scene.placeValid = _match.placeCue(x, y);
      return;
    }
    _aimAt(t);
  }

  void _onPanEnd() {
    if (_draggingCue) {
      _draggingCue = false;
      _scene.placing = false;
      _scene.placeValid = true;
      _setAimTowardNearestLegal();
    }
  }

  void _onTapUp(TapUpDetails d) {
    if (!_canAct) return;
    _aimAt(_toTable(d.localPosition));
  }

  void _powerStart(double x) {
    if (!_canAct) return;
    _charging = true;
    _chargeStartX = x;
  }

  void _powerUpdate(double x, double width) {
    if (!_charging || !_canAct) return;
    final double p = ((x - _chargeStartX).abs() / (width * 0.8)).clamp(0.0, 1.0).toDouble();
    setState(() => _power = p);
    _scene.pull = p;
  }

  void _powerEnd() {
    if (!_charging) return;
    _charging = false;
    final double p = _power;
    if (!_canAct || p < 0.04) {
      setState(() => _power = 0);
      _scene.pull = 0;
      return;
    }
    final PoolShot shot = PoolShot(
      dirX: math.cos(_scene.aimAngle),
      dirY: math.sin(_scene.aimAngle),
      power: p,
      spin: _spin,
      side: _side,
    );
    setState(() => _power = 0);
    _shoot(shot);
  }

  void _setSpinFrom(Offset local, double size) {
    final double r = size / 2;
    double sx = (local.dx - r) / (r * 0.72);
    double sy = -(local.dy - r) / (r * 0.72);
    final double l = math.sqrt(sx * sx + sy * sy);
    if (l > 1) {
      sx /= l;
      sy /= l;
    }
    setState(() {
      _side = sx;
      _spin = sy;
    });
  }

  // ---------------------------------------------------------------- build
  @override
  Widget build(BuildContext context) {
    _fa = context.isFa;
    _syncScene();
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        type: MaterialType.transparency,
        child: LayoutBuilder(builder: (BuildContext context, BoxConstraints box) {
          const double topH = 78;
          const double trayH = 26;
          const double bottomH = 104;
          final double availW = box.maxWidth - 12;
          final double availH = box.maxHeight - topH - trayH - bottomH - 8;
          final double s = math.max(0.05, math.min(availW / PoolConfig.artW, availH / PoolConfig.artH));
          _s = s;
          final double tw = PoolConfig.artW * s, th = PoolConfig.artH * s;
          final double left = (box.maxWidth - tw) / 2;
          final double top = topH + math.max(0.0, (availH - th) / 2);
          final double dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 2;
          return Stack(children: <Widget>[
            Positioned(left: 0, right: 0, top: 0, height: topH, child: _buildHud()),
            Positioned(
              left: left,
              top: top,
              width: tw,
              height: th,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: _onPanStart,
                onPanUpdate: _onPanUpdate,
                onPanEnd: (DragEndDetails d) => _onPanEnd(),
                onPanCancel: _onPanEnd,
                onTapUp: _onTapUp,
                child: Stack(fit: StackFit.expand, children: <Widget>[
                  Image.asset(
                    AppAssets.gamesBilliardsTableGreen,
                    fit: BoxFit.fill,
                    cacheWidth: math.max(64, (tw * dpr).round()),
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (BuildContext c, Object e, StackTrace? st) => const CustomPaint(painter: PoolTableFallbackPainter()),
                  ),
                  RepaintBoundary(child: CustomPaint(painter: PoolScenePainter(_scene))),
                ]),
              ),
            ),
            Positioned(left: left, top: top, width: tw, height: th, child: IgnorePointer(child: _buildBanner())),
            Positioned(left: 12, right: 12, top: top + th + 4, height: trayH - 4, child: _buildTray()),
            Positioned(left: 12, right: 12, bottom: 6, height: bottomH - 8, child: _buildControls()),
            if (_spinOpen) Positioned.fill(child: _buildSpinPicker()),
          ]);
        }),
      ),
    );
  }

  Widget _buildHud() {
    String sub(int seat) {
      final PoolGroup g = _match.groups[seat];
      if (_match.groupCleared(seat)) return _tx('نوبت توپ ۸', 'On the 8-ball');
      if (g == PoolGroup.solids) return _tx('ساده‌ها · ${_match.pottedCount(seat)}/۷', 'Solids · ${_match.pottedCount(seat)}/7');
      if (g == PoolGroup.stripes) return _tx('راه‌راه‌ها · ${_match.pottedCount(seat)}/۷', 'Stripes · ${_match.pottedCount(seat)}/7');
      return _match.isBreak ? _tx('بریک', 'Break') : _tx('میز باز', 'Open table');
    }

    final Set<int> potted = <int>{};
    for (int i = 1; i < 16; i++) {
      if (_match.balls[i].pocketed) potted.add(i);
    }
    final GmView? v = c.view;
    final int turn = v?.turn ?? _match.current;
    final bool over = _match.isOver || (v != null && !v.live);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Expanded(
          child: PoolPlayerCard(
            name: _name(0),
            subtitle: sub(0),
            group: _match.groups[0],
            pottedIds: potted,
            active: !over && turn == 0,
            accent: _p0Color,
            onEight: _match.groupCleared(0),
            alignEnd: false,
          ),
        ),
        const SizedBox(
          width: 44,
          child: Column(children: <Widget>[
            SizedBox(height: 10),
            PoolMiniBall(id: 8, size: 24),
            SizedBox(height: 4),
            Text('VS', style: TextStyle(color: NxColors.textDim, fontSize: 11, fontWeight: FontWeight.w900)),
          ]),
        ),
        Expanded(
          child: PoolPlayerCard(
            name: _name(1),
            subtitle: sub(1),
            group: _match.groups[1],
            pottedIds: potted,
            active: !over && turn == 1,
            accent: _p1Color,
            onEight: _match.groupCleared(1),
            alignEnd: true,
          ),
        ),
      ]),
    );
  }

  Widget _buildBanner() {
    final bool visible = _bannerLeft > 0 && _bannerText.isNotEmpty;
    return Align(
      alignment: const Alignment(0, -0.1),
      child: AnimatedSwitcher(
        duration: Duration(milliseconds: _reduced ? 1 : 260),
        child: !visible
            ? const SizedBox.shrink(key: ValueKey<String>('none'))
            : Container(
                key: ValueKey<int>(_bannerId),
                margin: const EdgeInsets.symmetric(horizontal: 26),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF050818).withOpacity(0.82),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _bannerColor.withOpacity(0.9), width: 1.4),
                  boxShadow: <BoxShadow>[BoxShadow(color: _bannerColor.withOpacity(0.45), blurRadius: 22)],
                ),
                child: Text(
                  _bannerText,
                  textAlign: TextAlign.center,
                  textDirection: _fa ? TextDirection.rtl : TextDirection.ltr,
                  style: TextStyle(color: _bannerColor, fontSize: 15, fontWeight: FontWeight.w800, height: 1.35),
                ),
              ),
      ),
    );
  }

  Widget _buildTray() {
    final GmView? v = c.view;
    String status;
    if (_match.isOver || (v != null && !v.live)) {
      status = _tx('پایان بازی', 'Game over');
    } else if (_replaying) {
      status = _tx('ضربه‌ی ${_name(_match.current)}…', '${_name(_match.current)} shoots…');
    } else if (_submitting) {
      status = _tx('ارسال ضربه…', 'Sending the shot…');
    } else if (_canAct && _match.ballInHand) {
      status = _match.kitchenOnly
          ? _tx('توپ سفید را پشت خط بکش', 'Drag the cue ball behind the line')
          : _tx('توپ در دست: سفید را جابه‌جا کن', 'Ball in hand: drag the cue ball');
    } else if (_canAct) {
      status = _tx('نوبت توست', 'Your turn');
    } else {
      status = _tx('نوبت ${_name(v?.turn ?? _match.current)}', "${_name(v?.turn ?? _match.current)}'s turn");
    }
    final List<Widget> items = <Widget>[
      for (int id = 1; id < 16; id++)
        if (_match.balls[id].pocketed) Padding(padding: const EdgeInsets.symmetric(horizontal: 1.5), child: PoolMiniBall(id: id, size: 17)),
    ];
    return Row(children: <Widget>[
      Expanded(child: SingleChildScrollView(scrollDirection: Axis.horizontal, reverse: true, child: Row(children: items))),
      const SizedBox(width: 8),
      Flexible(
        child: Text(
          status,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textDirection: _fa ? TextDirection.rtl : TextDirection.ltr,
          style: TextStyle(color: (v?.turn ?? _match.current) == 0 ? _p0Color : _p1Color, fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ),
    ]);
  }

  Widget _buildControls() {
    final bool enabled = _canAct && !_draggingCue;
    final String label = _power > 0
        ? _tx('قدرت ${(_power * 100).round()}٪', 'Power ${(_power * 100).round()}%')
        : _tx('بکش و رها کن', 'Pull & release');
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: <Widget>[
      GestureDetector(
        onTap: enabled ? () => setState(() => _spinOpen = true) : null,
        child: Container(
          width: 64,
          height: 88,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: const Color(0xFF0A0F2C).withOpacity(0.85),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: enabled ? NxColors.gold.withOpacity(0.7) : NxColors.glassBorder),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
            Expanded(child: FittedBox(fit: BoxFit.scaleDown, child: PoolSpinFace(side: _side, spin: _spin, size: 44))),
            const SizedBox(height: 3),
            Text(_tx('اسپین', 'Spin'),
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: TextStyle(color: enabled ? NxColors.gold : NxColors.textDim, fontSize: 10.5, fontWeight: FontWeight.w700, height: 1.1)),
          ]),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(mainAxisAlignment: MainAxisAlignment.end, children: <Widget>[
          PoolFineAimStrip(
            angle: _scene.aimAngle,
            enabled: enabled,
            label: _tx('تنظیم دقیق نشانه', 'Fine aim'),
            onDelta: (double dx) {
              if (!_canAct) return;
              _scene.aimAngle += dx * 0.0022;
              setState(() {});
            },
          ),
          const SizedBox(height: 8),
          PoolPowerBar(
            power: _power,
            enabled: enabled,
            label: label,
            onStart: _powerStart,
            onUpdate: _powerUpdate,
            onEnd: _powerEnd,
          ),
        ]),
      ),
    ]);
  }

  Widget _buildSpinPicker() {
    const double size = 190;
    return GestureDetector(
      onTap: () => setState(() => _spinOpen = false),
      child: Container(
        color: const Color(0xAA050818),
        alignment: Alignment.center,
        child: GestureDetector(
          onTap: () {},
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0F2C).withOpacity(0.95),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: NxColors.gold.withOpacity(0.7)),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
              Text(_tx('نقطه‌ی ضربه روی توپ سفید', 'Cue-ball contact point'),
                  textDirection: _fa ? TextDirection.rtl : TextDirection.ltr,
                  style: const TextStyle(color: NxColors.iceWhite, fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 14),
              GestureDetector(
                onPanDown: (DragDownDetails d) => _setSpinFrom(d.localPosition, size),
                onPanUpdate: (DragUpdateDetails d) => _setSpinFrom(d.localPosition, size),
                child: PoolSpinFace(side: _side, spin: _spin, size: size),
              ),
              const SizedBox(height: 14),
              Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                TextButton(
                  onPressed: () => setState(() {
                    _spin = 0;
                    _side = 0;
                  }),
                  child: Text(_tx('وسط', 'Center'), style: const TextStyle(color: NxColors.textDim)),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: NxColors.gold, foregroundColor: NxColors.navy),
                  onPressed: () => setState(() => _spinOpen = false),
                  child: Text(_tx('تأیید', 'Done'), style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
