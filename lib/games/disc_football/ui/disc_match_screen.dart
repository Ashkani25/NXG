// Offline match screen — port of the Godot build's src/screens/match.gd: pre-match setup, engine
// loop (stepped from DiscMatchView.onTick), touch drag aiming exactly like Godot (pick a disc of the
// side on turn, drag back like a slingshot, release to shoot), HUD, banners (goal art / no goal /
// golden goal), pause menu (resume, restart, loadout, graphics quality), mid-match loadout (formation
// applies at the next kickoff, ball + disc skins right away) and the end -> launch.onFinish (once).
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:nexora/games/core/game_contract.dart';
import '../core/data.dart';
import '../core/engine.dart';
import 'df_images.dart';
import 'disc_match_view.dart';
import 'formation_picker.dart';
import 'match_hud.dart';
import 'match_setup.dart';

class DiscMatchScreen extends StatefulWidget {
  const DiscMatchScreen({super.key, required this.launch});
  final GameLaunch launch;

  @override
  State<DiscMatchScreen> createState() => _DiscMatchScreenState();
}

class _DiscMatchScreenState extends State<DiscMatchScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  late final math.Random _rng = math.Random(widget.launch.seed);
  late final DfSetup _setup = DfSetup.load(_rng);
  final DiscMatchController _ctrl = DiscMatchController();
  Engine? _eng;
  bool _started = false;
  bool _paused = false;
  bool _ended = false;
  bool _finished = false;
  bool _loadoutOpen = false;
  bool _fancy = true;
  int? _pointer;
  List<String> _names = <String>['', ''];
  List<bool> _human = <bool>[true, false];
  final List<ui.Image?> _hudTex = <ui.Image?>[null, null];
  DfHudData? _hud;
  Timer? _endTimer;

  // banner
  // created eagerly in initState (a lazy `late final` would be first built inside dispose → ticker lookup on a dead element)
  late final AnimationController _banner;
  String _bTitle = '';
  String _bSub = '';
  Color _bCol = const Color(0xFF39D5FF);
  bool _bImg = false;

  GameLaunch get l => widget.launch;
  String tx(String fa, String en) => l.tx(fa, en);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _banner = AnimationController(vsync: this, duration: const Duration(milliseconds: 1950));
    _fancy = l.fancyEffects && !l.reducedMotion;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _endTimer?.cancel();
    _banner.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      if (_pointer != null) {
        _pointer = null;
        _eng?.cancel();
      }
      if (_started && !_ended && !_paused && mounted) setState(() => _paused = true);
    }
  }

  // ------------------------------------------------------------------ start
  void _start() {
    final bool ai = l.mode == GameMode.vsBot;
    final int lvl = l.difficulty == BotDifficulty.easy ? 0 : (l.difficulty == BotDifficulty.hard ? 2 : 1);
    final MatchCfg cfg = _setup.toCfg(ai: ai, aiLvl: lvl, oppForm: _rng.nextInt(kForms.length), seed: l.seed);
    final Engine e = Engine(cfg);
    _names = <String>[
      ai ? (l.playerName.isEmpty ? tx('تو', 'You') : l.playerName) : tx('بازیکن ۱', 'Player 1'),
      ai ? _setup.opp.name : tx('بازیکن ۲', 'Player 2'),
    ];
    _human = <bool>[true, !ai];
    for (int i = 0; i < 2; i++) {
      final int k = i;
      dfLoadImage(DfArt.team(cfg.teams[i]), width: 192).then((ui.Image? img) {
        if (mounted) setState(() => _hudTex[k] = img);
      });
    }
    setState(() {
      _eng = e;
      _started = true;
    });
    _haptic(1);
  }

  void _haptic(int k) {
    if (!l.soundOn) return;
    if (k >= 3) {
      HapticFeedback.heavyImpact();
    } else if (k == 2) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.lightImpact();
    }
  }

  // ------------------------------------------------------------------ loop
  void _tick(double dt) {
    final Engine? e = _eng;
    if (e == null) return;
    if (!_paused && !_loadoutOpen) e.update(dt);
    if (e.events.isNotEmpty) {
      final List<EngineEvent> evs = List<EngineEvent>.of(e.events);
      e.events.clear();
      for (final EngineEvent ev in evs) {
        _onEvent(ev);
      }
    }
    if (_pointer != null && e.drag == null) _pointer = null;
    _refreshHud(e);
  }

  void _refreshHud(Engine e) {
    final double mt = e.cfg.matchTime;
    final double tt = e.cfg.turnTime;
    String clock;
    if (mt > 0) {
      if (e.sudden) {
        clock = tx('گل طلایی', 'Golden goal');
      } else {
        final int m = math.max(0, e.mleft.ceil());
        clock = '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}';
      }
    } else {
      clock = tx('تا ${_faNum(e.cfg.limit)} گل', 'First to ${e.cfg.limit}');
    }
    final double frac = (tt > 0 && e.phase == Phase.aim) ? math.max(0.0, e.tleft / tt) : 1.0;
    final DfHudData d = DfHudData(
      s0: e.score[0],
      s1: e.score[1],
      turn: e.turn,
      clock: clock,
      sudden: e.sudden,
      frac: frac,
      bar: tt > 0,
      active: e.phase == Phase.aim,
    );
    final DfHudData? old = _hud;
    if (old == null || !old.same(d)) setState(() => _hud = d);
  }

  String _faNum(int n) {
    if (!l.isFa) return '$n';
    const String fa = '۰۱۲۳۴۵۶۷۸۹';
    return '$n'.split('').map((String c) => fa[int.parse(c)]).join();
  }

  void _onEvent(EngineEvent ev) {
    switch (ev.t) {
      case 'hit':
        if (ev.power > 0.35) _haptic(ev.power > 0.7 ? 2 : 1);
        break;
      case 'post':
        _haptic(2);
        break;
      case 'shot':
        _haptic(1);
        break;
      case 'goal':
        if (ev.nogoal) {
          _showBanner(tx('گل مردود', 'No goal'), tx('با ضربه‌ی اول نمی‌شه گل زد', "You can't score with the first shot"),
              const Color(0xFF8EA3D6), false);
        } else {
          _haptic(3);
          final int tm = ev.team == 1 ? 1 : 0;
          _showBanner(tx('گل!', 'GOAL!'), _names[tm], tm == 0 ? const Color(0xFF39D5FF) : const Color(0xFFFF4A5A), true);
        }
        break;
      case 'clock':
        _showBanner(tx('گل طلایی', 'Golden goal'), tx('گل بعدی برنده‌ست', 'Next goal wins'), const Color(0xFFFFD257), false);
        break;
      case 'end':
        if (!_ended) {
          _ended = true;
          _pointer = null;
          final List<int> sc = ev.score ?? <int>[_eng!.score[0], _eng!.score[1]];
          _endTimer = Timer(const Duration(milliseconds: 900), () => _finish(sc));
        }
        break;
      default:
        break;
    }
    _ctrl.onEvent(ev);
  }

  void _finish(List<int> sc) {
    if (_finished) return;
    _finished = true;
    final int a = sc[0], b = sc[1];
    final GameOutcome o = a > b ? GameOutcome.win : (a < b ? GameOutcome.loss : GameOutcome.draw);
    final bool local = l.mode == GameMode.local;
    String fa, en;
    if (local) {
      fa = a > b ? 'بازیکن ۱ برد · ${_faNum(a)} - ${_faNum(b)}' : (a < b ? 'بازیکن ۲ برد · ${_faNum(a)} - ${_faNum(b)}' : 'مساوی');
      en = a > b ? 'Player 1 wins · $a - $b' : (a < b ? 'Player 2 wins · $a - $b' : 'Draw');
    } else {
      fa = 'نتیجه ${_faNum(a)} - ${_faNum(b)} مقابل ${_names[1]}';
      en = 'Final $a - $b vs ${_names[1]}';
    }
    l.onFinish(GameResult(outcome: o, score: a, opponentScore: b, summaryFa: fa, summaryEn: en));
  }

  void _showBanner(String t, String s, Color c, bool img) {
    setState(() {
      _bTitle = t;
      _bSub = s;
      _bCol = c;
      _bImg = img;
    });
    _banner.forward(from: 0);
  }

  // ------------------------------------------------------------------ input (match.gd _on_touch)
  void _down(PointerDownEvent ev) {
    final Engine? e = _eng;
    if (_paused || _ended || _loadoutOpen || e == null || _pointer != null) return;
    final Offset w = _ctrl.toWorld(ev.localPosition);
    if (e.pick(w.dx, w.dy)) {
      _pointer = ev.pointer;
      _haptic(1);
    }
  }

  void _move(PointerMoveEvent ev) {
    if (ev.pointer != _pointer) return;
    final Offset w = _ctrl.toWorld(ev.localPosition);
    _eng?.move(w.dx, w.dy);
  }

  void _up(PointerUpEvent ev) {
    if (ev.pointer != _pointer) return;
    _pointer = null;
    final Engine? e = _eng;
    if (e == null) return;
    final Offset w = _ctrl.toWorld(ev.localPosition);
    e.move(w.dx, w.dy);
    e.release();
  }

  void _cancel(PointerCancelEvent ev) {
    if (ev.pointer != _pointer) return;
    _pointer = null;
    _eng?.cancel();
  }

  // ------------------------------------------------------------------ pause / restart / loadout
  void _setPaused(bool on) {
    if (on == _paused) return;
    if (on) {
      _eng?.cancel();
      _pointer = null;
    }
    setState(() => _paused = on);
  }

  void _restart() {
    final Engine? e = _eng;
    if (e == null || _finished) return;
    _endTimer?.cancel();
    e.restartMatch();
    _ended = false;
    _hud = null;
    setState(() => _paused = false);
  }

  Future<void> _openLoadout() async {
    final Engine? e = _eng;
    if (e == null || _ended || _loadoutOpen) return;
    e.cancel();
    _pointer = null;
    setState(() => _loadoutOpen = true);
    final DfLoadout v = DfLoadout(form: e.forms[0], team: _setup.team, ball: _setup.ball, field: _setup.field);
    int? newForm;
    await showDfLoadout(
      context,
      value: v,
      tx: tx,
      note: tx('ترکیب از شروع بعدی (بعد از گل) اعمال می‌شود؛ توپ و مهره همین حالا.',
          'Formation applies at the next kickoff (after a goal); ball and disc right away.'),
      onChange: () {
        if (v.ball != _setup.ball) {
          _setup.ball = v.ball;
          _ctrl.setSkin(ball: v.ball);
        }
        if (v.team != _setup.team) {
          _setup.team = v.team;
          _ctrl.setSkin(side: 0, teamId: v.team);
          dfLoadImage(DfArt.team(v.team), width: 192).then((ui.Image? img) {
            if (mounted) setState(() => _hudTex[0] = img);
          });
        }
        if (v.form != e.forms[0]) newForm = v.form;
      },
    );
    if (!mounted) return;
    final int? nf = newForm;
    if (nf != null && !_ended) {
      _setup.form = nf;
      e.forms = <int>[nf, e.forms[1]];
      if (e.phase == Phase.aim && e.shots == 0) e.reset(e.turn);
    }
    _setup.save();
    setState(() => _loadoutOpen = false);
  }

  // ------------------------------------------------------------------ build
  @override
  Widget build(BuildContext context) {
    if (!_started) {
      return DfSetupPanel(launch: l, setup: _setup, rng: _rng, onStart: _start);
    }
    final Engine e = _eng!;
    final MediaQueryData mq = MediaQuery.of(context);
    final double w = mq.size.width;
    final double hudH = (w * 0.15).clamp(46.0, 78.0).toDouble();
    final double top = mq.padding.top + 6;
    final bool rtl = Directionality.of(context) == TextDirection.rtl;
    final DfHudData hud = _hud ??
        DfHudData(s0: 0, s1: 0, turn: e.turn, clock: '', sudden: false, frac: 1, bar: e.cfg.turnTime > 0, active: true);
    return ColoredBox(
      color: const Color(0xFF02040C),
      child: Stack(children: <Widget>[
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _down,
            onPointerMove: _move,
            onPointerUp: _up,
            onPointerCancel: _cancel,
            child: DiscMatchView(
              engine: e,
              controller: _ctrl,
              ballSkin: _setup.ball,
              teamIds: e.cfg.teams,
              fancy: _fancy,
              topInset: top + hudH * 1.55 + 6,
              bottomInset: mq.padding.bottom + 16,
              onTick: _tick,
            ),
          ),
        ),
        Positioned(
          top: top,
          left: 8,
          right: 8,
          height: hudH,
          child: DfMatchHud(
            data: hud,
            names: _names,
            human: _human,
            teamImg: _hudTex,
            tx: tx,
            onPause: () => _setPaused(true),
            onLoadout: _openLoadout,
            // keep the host's exit button corner (top-start, 56 px) free
            pauseRight: !rtl,
            leftReserve: rtl ? 0 : 52,
            rightReserve: rtl ? 52 : 0,
          ),
        ),
        Positioned.fill(child: IgnorePointer(child: _bannerView(mq))),
        if (_paused) Positioned.fill(child: _pauseView()),
      ]),
    );
  }

  Widget _bannerView(MediaQueryData mq) {
    return AnimatedBuilder(
      animation: _banner,
      builder: (BuildContext context, Widget? child) {
        final double ms = _banner.value * 1950;
        if (_banner.value <= 0 || _banner.value >= 1) return const SizedBox.shrink();
        double sc, a;
        if (ms < 550) {
          sc = 0.3 + 0.7 * Curves.elasticOut.transform(ms / 550);
          a = math.min(1.0, ms / 120);
        } else if (ms < 1650) {
          sc = 1;
          a = 1;
        } else {
          final double u = (ms - 1650) / 300;
          sc = 1 + 0.25 * u;
          a = 1 - u;
        }
        return Align(
          alignment: const Alignment(0, -0.2),
          child: Opacity(opacity: a.clamp(0.0, 1.0).toDouble(), child: Transform.scale(scale: sc, child: child)),
        );
      },
      child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        if (_bImg)
          Image.asset(DfArt.bannerGoal(), width: mq.size.width * 0.62, errorBuilder: (BuildContext c, Object o, StackTrace? s) {
            return Text(_bTitle, style: _titleStyle(mq));
          })
        else
          Text(_bTitle, textAlign: TextAlign.center, style: _titleStyle(mq)),
        if (_bSub.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(_bSub,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color.lerp(_bCol, Colors.white, 0.2),
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  shadows: const <Shadow>[Shadow(color: Color(0xE6030512), blurRadius: 6)],
                )),
          ),
      ]),
    );
  }

  TextStyle _titleStyle(MediaQueryData mq) => TextStyle(
        color: Colors.white,
        fontSize: math.min(56.0, mq.size.width * 0.12),
        fontWeight: FontWeight.w900,
        shadows: <Shadow>[Shadow(color: _bCol, blurRadius: 24), Shadow(color: _bCol.withValues(alpha: 0.6), blurRadius: 8)],
      );

  Widget _pauseView() {
    Widget btn(String t, VoidCallback onTap, List<Color> cols) => GestureDetector(
          onTap: onTap,
          child: Container(
            height: 48,
            margin: const EdgeInsets.only(top: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(colors: cols),
              boxShadow: <BoxShadow>[BoxShadow(color: cols[0].withValues(alpha: 0.35), blurRadius: 14)],
            ),
            child: Text(t, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
          ),
        );
    return GestureDetector(
      onTap: () {},
      child: ColoredBox(
        color: const Color.fromRGBO(2, 4, 14, 0.7),
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.85, end: 1),
            duration: const Duration(milliseconds: 380),
            curve: Curves.easeOutBack,
            builder: (BuildContext c, double s, Widget? child) => Transform.scale(scale: s, child: child),
            child: Container(
              width: math.min(MediaQuery.of(context).size.width * 0.82, 420),
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
              decoration: BoxDecoration(
                color: const Color(0xE60B1230),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0x8039D5FF), width: 1.5),
                boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x5539D5FF), blurRadius: 30)],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                Text(tx('توقف', 'Paused'),
                    textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                btn(tx('ادامه', 'Resume'), () => _setPaused(false), const <Color>[Color(0xFF39D5FF), Color(0xFF2A6CFF)]),
                btn(tx('شروع دوباره', 'Restart'), _restart, const <Color>[Color(0xFF1A2558), Color(0xFF111A3E)]),
                btn(tx('ترکیب، توپ و مهره', 'Formation, ball & disc'), () {
                  _setPaused(false);
                  _openLoadout();
                }, const <Color>[Color(0xFF7B3FF2), Color(0xFF4B2AB0)]),
                const SizedBox(height: 14),
                Text(tx('کیفیت گرافیک', 'Graphics quality'),
                    textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF8EA3D6), fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                DfSegmented(
                  labels: <String>[tx('بالا', 'High'), tx('روان', 'Smooth')],
                  index: _fancy ? 0 : 1,
                  color: const Color(0xFF9B5CFF),
                  onChanged: (int i) => setState(() => _fancy = i == 0),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
