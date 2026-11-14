import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nexora/games/core/game_contract.dart';
import 'package:nexora/games/kit_v2/ui/kit_v2_sprites.dart';
import 'package:nexora/games/kit_v2/ui/kit_v2_widgets.dart';

import '../core/ludo_bot.dart';
import '../core/ludo_rules.dart';
import 'ludo_board.dart';
import 'ludo_die.dart';

class _Flight {
  const _Flight(this.seat, this.token, this.path);
  final int seat;
  final int token;
  final List<Offset> path;
}

class LudoGame extends StatefulWidget {
  const LudoGame({super.key, required this.launch});
  final GameLaunch launch;

  @override
  State<LudoGame> createState() => _LudoGameState();
}

class _LudoGameState extends State<LudoGame> with TickerProviderStateMixin {
  late LudoEngine _engine;
  late List<LudoBot?> _bots;
  late AnimationController _rollCtl;
  late AnimationController _hopCtl;
  late AnimationController _pulseCtl;
  late AnimationController _flashCtl;

  int? _dieValue;
  bool _rolling = false;
  bool _busy = false;
  bool _finished = false;
  List<LudoMove> _moves = <LudoMove>[];
  List<_Flight> _flights = <_Flight>[];
  late List<int> _captures;
  Offset? _flashAt;
  int _lastHopSegment = -1;
  String _statusFa = '';
  String _statusEn = '';
  String? _bannerFa;
  String? _bannerEn;

  GameLaunch get _l => widget.launch;
  bool get _fancy => _l.fancyEffects && !_l.reducedMotion;
  LudoState get _s => _engine.state;
  int get _n => _s.playerCount;

  @override
  void initState() {
    super.initState();
    final int seed = _l.seed ?? DateTime.now().microsecondsSinceEpoch;
    _engine = LudoEngine(playerCount: _l.playerCount, seed: seed);
    _captures = List<int>.filled(_n, 0);
    _bots = List<LudoBot?>.generate(
        _n,
        (int i) => (_l.vsBot && i != 0)
            ? LudoBot(level: _l.difficulty.index, seed: seed + 31 * (i + 1))
            : null);
    _rollCtl = AnimationController(
        vsync: this, duration: Duration(milliseconds: _l.reducedMotion ? 250 : 700));
    _hopCtl = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _hopCtl.addListener(_onHopTick);
    _pulseCtl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    if (_l.reducedMotion) {
      _pulseCtl.value = 0.8;
    } else {
      _pulseCtl.repeat(reverse: true);
    }
    _flashCtl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    WidgetsBinding.instance.addPostFrameCallback((_) => _beginTurn());
    KitSprites.preload(kKitSeatPieces, width: 128).then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _hopCtl.removeListener(_onHopTick);
    _rollCtl.dispose();
    _hopCtl.dispose();
    _pulseCtl.dispose();
    _flashCtl.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------- helpers
  bool _isBot(int seat) => _bots[seat] != null;

  Color _color(int seat) => kLudoSeatColors[seat % kLudoSeatColors.length];

  static const String _faDigits = '۰۱۲۳۴۵۶۷۸۹';
  String _faNum(int v) =>
      v.toString().split('').map((String c) => _faDigits[int.parse(c)]).join();

  String _nameFa(int seat) {
    if (seat == 0) return _l.playerName;
    if (_l.vsBot) return _n == 2 ? 'ربات NX' : 'ربات ${_faNum(seat)}';
    return 'بازیکن ${_faNum(seat + 1)}';
  }

  String _nameEn(int seat) {
    if (seat == 0) return _l.playerName;
    if (_l.vsBot) return _n == 2 ? 'NX Bot' : 'Bot $seat';
    return 'Player ${seat + 1}';
  }

  String _name(int seat) => _l.isFa ? _nameFa(seat) : _nameEn(seat);

  void _status(String fa, String en) {
    _statusFa = fa;
    _statusEn = en;
  }

  Future<void> _wait(int ms) => Future<void>.delayed(
      Duration(milliseconds: _l.reducedMotion ? (ms * 0.6).round() : ms));

  void _haptic({bool heavy = false}) {
    if (!_l.soundOn) return;
    if (heavy) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.selectionClick();
    }
  }

  void _onHopTick() {
    if (_flights.isEmpty) return;
    final int segs = _flights.first.path.length - 1;
    if (segs <= 0) return;
    final int seg = min(segs - 1, (_hopCtl.value * segs).floor());
    if (seg != _lastHopSegment) {
      _lastHopSegment = seg;
      if (seg > 0) _haptic();
    }
  }

  // ------------------------------------------------------------------ flow
  void _beginTurn() {
    if (!mounted || _finished) return;
    final int seat = _s.turn;
    setState(() {
      _moves = <LudoMove>[];
      if (_isBot(seat)) {
        _status('نوبت ${_nameFa(seat)}', "${_nameEn(seat)}'s turn");
      } else {
        _status('نوبت ${_nameFa(seat)} — تاس را لمس کن', '${_nameEn(seat)} — tap the die');
      }
    });
    if (_isBot(seat)) _botTurn(seat);
  }

  Future<void> _botTurn(int seat) async {
    await _wait(550 + Random().nextInt(350));
    if (!mounted || _finished || _s.turn != seat) return;
    await _roll(fromBot: true);
  }

  Future<void> _roll({bool fromBot = false}) async {
    if (_rolling || _busy || _moves.isNotEmpty || _finished) return;
    final int seat = _s.turn;
    if (_isBot(seat) && !fromBot) return;
    setState(() => _rolling = true);
    _haptic();
    await _rollCtl.forward(from: 0);
    if (!mounted) return;
    final LudoRollResult r = _engine.roll();
    _haptic(heavy: true);
    setState(() {
      _rolling = false;
      _dieValue = r.roll;
    });
    if (r.forfeited) {
      setState(() => _status('سه شش پشت سر هم — نوبت سوخت!', 'Three sixes in a row — turn lost!'));
      await _wait(1300);
      _beginTurn();
      return;
    }
    if (r.rollAgain) {
      setState(() => _status('حرکتی نیست، ولی شش آوردی — دوباره بریز', 'No move, but a six — roll again'));
      await _wait(900);
      _beginTurn();
      return;
    }
    if (r.moves.isEmpty) {
      setState(() => _status('حرکتی ممکن نیست', 'No possible move'));
      await _wait(900);
      _beginTurn();
      return;
    }
    setState(() => _moves = r.moves);
    final LudoBot? bot = _bots[seat];
    if (bot != null) {
      setState(() => _status('${_nameFa(seat)} فکر می‌کند…', '${_nameEn(seat)} is thinking…'));
      await _wait(420 + _l.difficulty.index * 120);
      if (!mounted) return;
      await _playMove(bot.choose(_s, r.moves));
      return;
    }
    if (_allSame(r.moves)) {
      await _wait(320);
      if (!mounted) return;
      await _playMove(r.moves.first);
      return;
    }
    setState(() => _status('یک مهره‌ی درخشان را انتخاب کن', 'Pick a glowing token'));
  }

  bool _allSame(List<LudoMove> moves) {
    for (final LudoMove m in moves) {
      if (m.from != moves.first.from || m.to != moves.first.to) return false;
    }
    return true;
  }

  List<Offset> _pathFor(LudoState s, LudoMove m) {
    final List<Offset> path = <Offset>[];
    if (m.from == kLudoBase) {
      path.add(LudoGeom.cellFor(s, m.seat, m.token, kLudoBase));
      path.add(LudoGeom.cellFor(s, m.seat, m.token, 0));
      return path;
    }
    for (int p = m.from; p <= m.to; p++) {
      path.add(LudoGeom.cellFor(s, m.seat, m.token, p));
    }
    return path;
  }

  Future<void> _fly(List<_Flight> flights, int ms) async {
    _lastHopSegment = -1;
    setState(() => _flights = flights);
    _hopCtl.duration = Duration(milliseconds: max(120, _l.reducedMotion ? ms ~/ 2 : ms));
    await _hopCtl.forward(from: 0);
  }

  Future<void> _playMove(LudoMove m) async {
    if (_busy) return;
    _busy = true;
    setState(() => _moves = <LudoMove>[]);
    final LudoState before = _s.copy();
    final List<Offset> path = _pathFor(before, m);
    await _fly(<_Flight>[_Flight(m.seat, m.token, path)], (path.length - 1) * 165);
    if (!mounted) return;
    final Offset landing = path.last;
    final LudoPlayResult res = _engine.play(m);
    if (m.captures.isNotEmpty) {
      _captures[m.seat] += m.captures.length;
      final List<_Flight> back = m.captures
          .map((LudoCapture c) => _Flight(
              c.seat, c.token, <Offset>[landing, LudoGeom.cellFor(_s, c.seat, c.token, kLudoBase)]))
          .toList();
      setState(() {
        _flights = <_Flight>[];
        _flashAt = landing;
        _status('ضربه! ${_nameFa(m.seat)} مهره را به پایگاه فرستاد',
            'Hit! ${_nameEn(m.seat)} sends a token back to base');
      });
      _haptic(heavy: true);
      if (_fancy) _flashCtl.forward(from: 0);
      await _fly(back, 480);
      if (!mounted) return;
    }
    setState(() => _flights = <_Flight>[]);
    _busy = false;
    if (res.won) {
      _gameOver(m.seat);
      return;
    }
    if (res.extraTurn) {
      setState(() {
        if (m.finishes) {
          _status('مهره به خانه رسید — نوبت اضافه!', 'Token home — extra turn!');
        } else if (m.captures.isEmpty) {
          _status('شش! یک نوبت دیگر', 'Six! Roll again');
        }
      });
      await _wait(m.captures.isEmpty ? 380 : 650);
      if (!mounted) return;
      final int seat = _s.turn;
      if (_isBot(seat)) {
        _botTurn(seat);
      } else {
        setState(() => _status(
            '${_nameFa(seat)}، دوباره تاس را لمس کن', '${_nameEn(seat)}, tap the die again'));
      }
      return;
    }
    await _wait(250);
    _beginTurn();
  }

  void _onBoardTap(Offset local, double boardSize) {
    if (_moves.isEmpty || _busy || _isBot(_s.turn)) return;
    final double u = boardSize / 15;
    final Offset p = local / u;
    LudoMove? best;
    double bestD = 0.9;
    for (final LudoMove m in _moves) {
      final Offset c = LudoGeom.cellFor(_s, m.seat, m.token, m.from);
      final double d = (c - p).distance;
      if (d < bestD) {
        bestD = d;
        best = m;
      }
    }
    final LudoMove? chosen = best;
    if (chosen != null) _playMove(chosen);
  }

  void _gameOver(int winner) {
    if (_finished) return;
    _finished = true;
    _haptic(heavy: true);
    setState(() {
      _bannerFa = '${_nameFa(winner)} برنده شد!';
      _bannerEn = '${_nameEn(winner)} wins!';
      _status('همه‌ی مهره‌ها در خانه', 'All tokens home');
    });
    int bestOther = 0;
    for (int i = 1; i < _n; i++) {
      bestOther = max(bestOther, _s.homeCount(i));
    }
    final int mine = _s.homeCount(0);
    final String fa =
        'برنده: ${_nameFa(winner)}. مهره‌های تو در خانه: ${_faNum(mine)}/۴ • ضربه‌های تو: ${_faNum(_captures[0])} • بازیکنان: ${_faNum(_n)}';
    final String en =
        'Winner: ${_nameEn(winner)}. Your tokens home: $mine/4 • your captures: ${_captures[0]} • players: $_n';
    Future<void>.delayed(const Duration(milliseconds: 1800), () {
      if (!mounted) return;
      _l.onFinish(GameResult(
        outcome: winner == 0 ? GameOutcome.win : GameOutcome.loss,
        score: mine,
        opponentScore: winner == 0 ? bestOther : _s.homeCount(winner),
        summaryFa: fa,
        summaryEn: en,
      ));
    });
  }

  // ------------------------------------------------------------------ build
  List<LudoTokenDraw> _tokenDraws() {
    final Map<String, List<List<int>>> groups = <String, List<List<int>>>{};
    final Set<String> flying = _flights.map((_Flight f) => '${f.seat}:${f.token}').toSet();
    final Set<String> movable = _moves.map((LudoMove m) => '${m.seat}:${m.token}').toSet();
    for (int seat = 0; seat < _n; seat++) {
      for (int t = 0; t < kLudoTokens; t++) {
        if (flying.contains('$seat:$t')) continue;
        final Offset c = LudoGeom.cellFor(_s, seat, t, _s.tokens[seat][t]);
        final String key = '${c.dx.toStringAsFixed(2)},${c.dy.toStringAsFixed(2)}';
        groups.putIfAbsent(key, () => <List<int>>[]).add(<int>[seat, t]);
      }
    }
    final List<LudoTokenDraw> out = <LudoTokenDraw>[];
    groups.forEach((String key, List<List<int>> members) {
      final int n = members.length;
      for (int i = 0; i < n; i++) {
        final int seat = members[i][0];
        final int t = members[i][1];
        Offset c = LudoGeom.cellFor(_s, seat, t, _s.tokens[seat][t]);
        double scale = 1;
        if (n > 1) {
          scale = n == 2 ? 0.8 : 0.68;
          final double a = 2 * pi * i / n - pi / 4;
          c = c + Offset(cos(a), sin(a)) * 0.2;
        }
        out.add(LudoTokenDraw(
          pos: c,
          color: _color(seat),
          scale: scale,
          movable: movable.contains('$seat:$t') && !_isBot(seat),
        ));
      }
    });
    final double v = _hopCtl.value;
    for (final _Flight f in _flights) {
      final int segs = f.path.length - 1;
      if (segs <= 0) {
        out.add(LudoTokenDraw(pos: f.path.first, color: _color(f.seat)));
        continue;
      }
      double x = v * segs;
      if (x < 0) x = 0;
      if (x > segs) x = segs.toDouble();
      final int i = min(segs - 1, x.floor());
      final double local = x - i;
      final Offset pos = Offset.lerp(f.path[i], f.path[i + 1], local)!;
      final double lift = sin(local * pi) * (segs == 1 ? 0.8 : 0.45);
      out.add(LudoTokenDraw(pos: pos, color: _color(f.seat), lift: lift, scale: 1.05));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Positioned.fill(child: _background()),
        SafeArea(
          child: Column(
            children: <Widget>[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 64),
                child: _playersBar(),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Center(
                    child: KitBoardFrame(glow: _fancy, child: _boardView()),
                  ),
                ),
              ),
              _bottomBar(),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ],
    );
  }

  Widget _background() {
    // kit_v2 game room; sparse stars on top keep the cosmic feel.
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        const KitRoomBackground(veil: 0.4),
        CustomPaint(painter: _LudoStars(_fancy ? 70 : 24)),
      ],
    );
  }

  Widget _playersBar() {
    final List<KitSeat> seats = <KitSeat>[];
    for (int seat = 0; seat < _n; seat++) {
      final Color col = _color(seat);
      seats.add(KitSeat(
        name: _name(seat),
        subtitle: '★ ${_s.homeCount(seat)}/4  ${_l.tx('در خانه', 'home')}',
        color: col,
        active: _s.turn == seat && !_finished,
        piece: kitPieceForColor(col),
      ));
    }
    return KitSeatsHud(seats: seats, reducedMotion: !_fancy);
  }

  Widget _boardView() {
    final List<Color?> cornerColors = List<Color?>.filled(4, null);
    for (int seat = 0; seat < _n; seat++) {
      cornerColors[_s.corners[seat]] = _color(seat);
    }
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) {
          final double size = min(c.maxWidth, c.maxHeight);
          return Directionality(
            textDirection: TextDirection.ltr,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (TapUpDetails d) => _onBoardTap(d.localPosition, size),
              child: SizedBox(
                width: size,
                height: size,
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: LudoBoardPainter(cornerColors: cornerColors, fancy: _fancy),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: AnimatedBuilder(
                        animation: Listenable.merge(<Listenable>[_hopCtl, _pulseCtl, _flashCtl]),
                        builder: (BuildContext context, Widget? child) => CustomPaint(
                          painter: LudoTokensPainter(
                            tokens: _tokenDraws(),
                            pulse: _pulseCtl.value,
                            fancy: _fancy,
                            flashAt: _flashAt,
                            flash: _flashCtl.value,
                          ),
                        ),
                      ),
                    ),
                    if (_bannerFa != null) _banner(size),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _banner(double size) {
    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.5, end: 1),
        duration: const Duration(milliseconds: 650),
        curve: Curves.elasticOut,
        builder: (BuildContext c, double v, Widget? child) =>
            Transform.scale(scale: v, child: child),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: size * 0.06, vertical: size * 0.04),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            color: const Color(0xE60A0F2C),
            border: Border.all(color: const Color(0xFFFFC857), width: 2),
            boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x88FFC857), blurRadius: 30)],
          ),
          child: Text(
            _l.isFa ? (_bannerFa ?? '') : (_bannerEn ?? ''),
            textAlign: TextAlign.center,
            textDirection: _l.isFa ? TextDirection.rtl : TextDirection.ltr,
            style: TextStyle(
                color: const Color(0xFFFFC857),
                fontSize: size * 0.07,
                fontWeight: FontWeight.w900),
          ),
        ),
      ),
    );
  }

  Widget _bottomBar() {
    final int seat = _s.turn;
    final bool canTap = !_isBot(seat) && !_rolling && !_busy && _moves.isEmpty && !_finished;
    final Color col = _color(seat);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: <Widget>[
          GestureDetector(
            onTap: canTap ? () => _roll() : null,
            child: AnimatedBuilder(
              animation: Listenable.merge(<Listenable>[_rollCtl, _pulseCtl]),
              builder: (BuildContext context, Widget? child) {
                final double breathe = canTap ? 1 + 0.06 * _pulseCtl.value : 1;
                return Transform.scale(
                  scale: breathe,
                  child: KitRollingDie(
                    value: _dieValue,
                    size: 64,
                    rolling: _rolling,
                    t: _rollCtl.value,
                    glow: (_fancy || canTap) ? col : null,
                    fallback: LudoDie(
                      value: _dieValue,
                      color: col,
                      size: 64,
                      glow: _fancy || canTap,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: Text(
                _l.isFa ? _statusFa : _statusEn,
                key: ValueKey<String>(_statusFa + _statusEn),
                style: const TextStyle(
                    color: Color(0xFFEAF6FF), fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LudoStars extends CustomPainter {
  _LudoStars(this.count);
  final int count;

  @override
  void paint(Canvas canvas, Size size) {
    final Random r = Random(11);
    final Paint p = Paint();
    for (int i = 0; i < count; i++) {
      p.color = (i % 5 == 0 ? const Color(0xFFFF4FA3) : const Color(0xFFEAF6FF))
          .withValues(alpha: 0.2 + r.nextDouble() * 0.6);
      canvas.drawCircle(
          Offset(r.nextDouble() * size.width, r.nextDouble() * size.height),
          r.nextDouble() * 1.5 + 0.3,
          p);
    }
  }

  @override
  bool shouldRepaint(covariant _LudoStars oldDelegate) => oldDelegate.count != count;
}
