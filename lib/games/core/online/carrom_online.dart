/// Online Carrom board (host-authoritative, see carrom_online_sync.dart for the wire format).
///
///  * my turn: I place / aim exactly like offline; my device simulates the shot with the
///    offline engine, then submits the final board via `gm_shot` (next turn + finish included);
///  * opponent / spectator: the new board arrives with the `prev` board + the shot, and this
///    device replays the same deterministic simulation for the animation, then snaps to the
///    submitted board (so a float difference can never desync the match);
///  * the server owns the clock (45 s): the top bar shows it; on an idle timeout the server
///    passes the turn and both clients apply [CrMatch.passTurn].
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexora/core/assets/app_assets.dart';
import 'package:nexora/core/settings/app_settings.dart';
import 'package:nexora/games/carrom/core/carrom_config.dart';
import 'package:nexora/games/carrom/core/carrom_match.dart';
import 'package:nexora/games/carrom/ui/cr_controller.dart';
import 'package:nexora/games/carrom/ui/cr_fx.dart';
import 'package:nexora/games/carrom/ui/cr_painter.dart';
import 'package:nexora/games/core/game_contract.dart';
import 'package:nexora/games/kit_v2/ui/kit_v2_widgets.dart';

import 'carrom_online_sync.dart';
import 'gm_match_controller.dart';
import 'gm_models.dart';

/// Online board for a live carrom match.
Widget buildCarromOnline(GmMatchController c) => CarromOnlineBoard(c: c);

/// Extra line on the result card: coins per side + queen.
String? carromOnlineResultDetail(BuildContext context, GmView v) {
  final CrMatch m = CarromOnlineSync.derive(v);
  final String q = m.queenCoveredBy >= 0 ? context.tx(' · ملکه: ', ' · queen: ') + v.nameOf(m.queenCoveredBy) : '';
  return '${v.nameOf(0)} ${m.pocketedCount(0)} – ${m.pocketedCount(1)} ${v.nameOf(1)}$q';
}

/// [CrController] driven by the server: input only on my turn, no local turn timer, shots
/// recorded for submission, opponent shots replayed.
class CarromOnlineController extends CrController {
  CarromOnlineController(super.launch, this.gm);

  final GmMatchController gm;

  int appliedVersion = -1;
  int appliedShots = -1;
  bool replaying = false;
  bool submitting = false;
  bool _dead = false;
  GmView? _pendingView;
  GmView? _replayTarget;
  CrMatch? _prev;
  CrShot? _shot;

  /// Short status message (fa, en) shown in the HUD.
  final ValueNotifier<String> note = ValueNotifier<String>('');

  GmView? get view => gm.view;

  bool get canShoot {
    final GmView? v = gm.view;
    if (v == null || !v.myTurn || replaying || submitting) return false;
    if (appliedVersion != v.version) return false;
    return match.phase == CrPhase.aiming && match.turn == v.mySeat;
  }

  @override
  bool get humanCanAim => super.humanCanAim && canShoot;

  @override
  String seatName(int seat) {
    final GmView? v = gm.view;
    if (v == null) return super.seatName(seat);
    final String n = v.nameOf(seat);
    return v.mySeat == seat ? '$n ${launch.tx('(تو)', '(you)')}' : n;
  }

  @override
  void startShot(CrShot shot) {
    if (!replaying) {
      if (!canShoot || match.validate(shot) != null) return;
      _prev = match.clone();
      _shot = shot;
    }
    super.startShot(shot);
  }

  @override
  void tick(double dt) {
    if (_dead) return;
    timeLeft = CrConfig.turnSeconds; // the server owns the clock
    final bool wasSim = match.phase == CrPhase.simulating;
    super.tick(dt);
    if (wasSim && match.phase != CrPhase.simulating) _onSettled();
  }

  /// Copies [m] into the controller's match (the painter reads `match` every frame).
  void load(CrMatch m) {
    match.bodies = m.bodies;
    match.turn = m.turn;
    match.turnNumber = m.turnNumber;
    match.phase = m.phase;
    match.winner = m.winner;
    match.queenPendingFor = m.queenPendingFor;
    match.queenCoveredBy = m.queenCoveredBy;
    match.points = List<int>.from(m.points);
    trail.clear();
    aiming = false;
    pull = Offset.zero;
    final int seat = match.turn;
    if (match.phase == CrPhase.aiming && !match.placementOk(placeX[seat])) {
      final double? x = match.nearestPlacement(placeX[seat]);
      if (x != null) placeX[seat] = x;
    }
  }

  /// A new server view (every accepted version).
  void onView(GmView v) {
    if (_dead) return;
    if (v.version <= appliedVersion && appliedVersion >= 0) return;
    if (match.phase == CrPhase.simulating || submitting) {
      _pendingView = v;
      return;
    }
    if (CarromOnlineSync.shouldReplay(v, appliedShots)) {
      final CrMatch? prev = CarromOnlineSync.boardFrom(v.state['prev']);
      final CrShot? shot = CarromOnlineSync.shotFrom(v.state['shot']);
      if (prev != null && shot != null) {
        load(prev);
        if (match.validate(shot) == null) {
          placeX[match.turn] = shot.placeX;
          appliedVersion = v.version;
          appliedShots = CarromOnlineSync.shotsOf(v);
          _replayTarget = v;
          replaying = true;
          super.startShot(shot);
          notifyListeners();
          return;
        }
      }
    }
    _apply(v);
  }

  void _apply(GmView v) {
    final int before = appliedShots;
    load(CarromOnlineSync.derive(v));
    appliedVersion = v.version;
    appliedShots = CarromOnlineSync.shotsOf(v);
    replaying = false;
    _replayTarget = null;
    final Map<String, dynamic> foul = gmMap(v.state['foul']);
    if (before >= 0 && appliedShots == before && foul['reason'] == 'timeout') {
      final int s = gmInt(foul['seat'], -1);
      note.value = s == v.mySeat
          ? launch.tx('وقتت تمام شد؛ نوبت سوخت', 'Time up — you lost the turn')
          : launch.tx('وقت حریف تمام شد؛ نوبت توست', 'Opponent timed out — your turn');
    } else if (v.live && v.myTurn) {
      note.value = launch.tx('نوبت توست — استرایکر را جابه‌جا کن و بکش', 'Your turn — slide the striker, drag and release');
    } else if (v.live) {
      note.value = launch.tx('نوبت ${v.nameOf(v.turn)}', "${v.nameOf(v.turn)}'s turn");
    }
    notifyListeners();
    // A board that ended without a shot (turn limit through idle timeouts): the shooter closes it.
    if (v.live && v.myTurn && match.phase == CrPhase.finished) {
      final Map<String, dynamic>? fin = CarromOnlineSync.finishOf(match);
      if (fin != null) {
        submitting = true;
        final Map<String, dynamic> st = <String, dynamic>{
          if (v.state['seed'] != null) 'seed': v.state['seed'],
          'board': match.toJson(),
          'scores': CarromOnlineSync.scoresOf(match),
        };
        gm.shot(st, match.turn == 1 ? 1 : 0, finish: fin).whenComplete(_afterSubmit);
      }
    }
  }

  void _onSettled() {
    if (replaying) {
      replaying = false;
      final GmView? t = _replayTarget;
      _replayTarget = null;
      final GmView? next = _pendingView;
      _pendingView = null;
      if (t != null) {
        final int want = gmInt(t.state['hash']);
        if (want != 0 && want != match.stateHash()) {
          debugPrint('carrom online: replay hash mismatch ${match.stateHash()} != $want (snapping)');
        }
        _apply(t);
      }
      if (next != null) onView(next);
      return;
    }
    if (_prev != null && _shot != null) {
      unawaited(_submit());
    }
  }

  Future<void> _submit() async {
    final CrMatch? prev = _prev;
    final CrShot? shot = _shot;
    final GmView? v = gm.view;
    if (prev == null || shot == null || v == null) return;
    submitting = true;
    notifyListeners();
    final Map<String, dynamic> state = CarromOnlineSync.encode(
      prev: prev,
      shot: shot,
      after: match,
      shooter: prev.turn,
      seed: v.state['seed'],
    );
    final Map<String, dynamic>? fin = CarromOnlineSync.finishOf(match);
    final int next = CarromOnlineSync.nextTurn(match);
    final int version = v.version;
    bool ok = await gm.shot(state, next, finish: fin);
    if (!ok && !_dead) {
      // one retry for a flaky network, only if nothing moved on the server
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      final GmView? cur = gm.view;
      if (!_dead && cur != null && cur.version == version && cur.myTurn) {
        ok = await gm.shot(state, next, finish: fin);
      }
    }
    _prev = null;
    _shot = null;
    if (!ok) appliedVersion = -1; // resync to the server's board
    _afterSubmit();
  }

  void _afterSubmit() {
    submitting = false;
    if (_dead) return;
    final GmView? latest = gm.view;
    final GmView? pending = _pendingView;
    _pendingView = null;
    if (pending != null) onView(pending);
    if (latest != null && (appliedVersion < 0 || latest.version > appliedVersion)) onView(latest);
    notifyListeners();
  }

  @override
  void dispose() {
    _dead = true;
    note.dispose();
    super.dispose();
  }
}

GameLaunch _onlineLaunch(BuildContext context) {
  final bool fa = context.isFa;
  bool fancy = true;
  bool reduced = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  bool haptics = true;
  try {
    final AppSettings s = ProviderScope.containerOf(context, listen: false).read(settingsProvider);
    fancy = s.fancyEffects;
    reduced = s.reducedMotion;
    haptics = s.haptics;
  } catch (_) {/* no ProviderScope (tests): defaults */}
  return GameLaunch(
    gameId: 'carrom',
    mode: GameMode.local,
    difficulty: BotDifficulty.normal,
    playerName: '',
    isFa: fa,
    fancyEffects: fancy && !reduced,
    reducedMotion: reduced,
    soundOn: haptics,
    onFinish: (GameResult _) {},
  );
}

class CarromOnlineBoard extends StatefulWidget {
  const CarromOnlineBoard({super.key, required this.c});
  final GmMatchController c;

  @override
  State<CarromOnlineBoard> createState() => _CarromOnlineBoardState();
}

class _CarromOnlineBoardState extends State<CarromOnlineBoard> with SingleTickerProviderStateMixin {
  CarromOnlineController? _cc;
  Ticker? _ticker;
  StreamSubscription<GmView>? _sub;
  final CrImages _images = CrImages();
  Duration _last = Duration.zero;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_cc != null) return;
    final CarromOnlineController cc = CarromOnlineController(_onlineLaunch(context), widget.c);
    _cc = cc;
    final GmView? v = widget.c.view;
    if (v != null) cc.onView(v);
    _sub = widget.c.views.listen(cc.onView);
    _ticker = createTicker(_onTick)..start();
    _loadImages();
  }

  Future<void> _loadImages() async {
    ui.Image? board = await crLoadImage(AppAssets.kitV2BoardsBoardCarrom, 1024);
    final bool kitBoard = board != null;
    board ??= await crLoadImage(AppAssets.gamesCarromBoardNxBlackGold, 1024);
    final ui.Image? white = await crLoadImage(AppAssets.kitV2PiecesCoinWhite1, 96) ??
        await crLoadImage(AppAssets.gamesSharedDiscsDiscCream, 96);
    final ui.Image? black = await crLoadImage(AppAssets.kitV2PiecesCoinDark1, 96) ??
        await crLoadImage(AppAssets.gamesSharedDiscsDiscBlack, 96);
    final ui.Image? queen = await crLoadImage(AppAssets.kitV2PiecesCoinQueen, 96) ??
        await crLoadImage(AppAssets.disc('disc_red'), 96);
    final ui.Image? s0 = await crLoadImage(AppAssets.kitV2PiecesStrikerCyan, 128);
    final ui.Image? s1 = await crLoadImage(AppAssets.kitV2PiecesStrikerSilver, 128);
    if (!mounted) return;
    setState(() {
      _images.board = board;
      _images.boardIsKit = kitBoard;
      _images.white = white;
      _images.black = black;
      _images.queen = queen;
      _images.striker0 = s0;
      _images.striker1 = s1;
    });
  }

  void _onTick(Duration elapsed) {
    double dt = (elapsed - _last).inMicroseconds / 1000000.0;
    _last = elapsed;
    if (dt < 0) dt = 0;
    if (dt > 0.05) dt = 0.05;
    _cc?.tick(dt);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ticker?.dispose();
    _cc?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final CarromOnlineController? cc = _cc;
    if (cc == null) return const SizedBox.shrink();
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        type: MaterialType.transparency,
        child: Stack(children: <Widget>[
          const Positioned.fill(child: IgnorePointer(child: KitRoomBackground())),
          Column(children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
              child: AnimatedBuilder(animation: cc, builder: (BuildContext context, Widget? _) => _CarromOnlineHud(cc: cc)),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints cons) {
                    cc.viewSize = Size(cons.maxWidth, cons.maxHeight);
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (DragStartDetails d) => cc.onPanStart(d.localPosition),
                      onPanUpdate: (DragUpdateDetails d) => cc.onPanUpdate(d.localPosition),
                      onPanEnd: (DragEndDetails d) => cc.onPanEnd(),
                      onPanCancel: cc.onPanCancel,
                      child: CustomPaint(
                        size: Size(cons.maxWidth, cons.maxHeight),
                        painter: CrPainter(cc, _images),
                      ),
                    );
                  },
                ),
              ),
            ),
            _CarromOnlinePlacementBar(cc: cc),
          ]),
        ]),
      ),
    );
  }
}

class _CarromOnlineHud extends StatelessWidget {
  const _CarromOnlineHud({required this.cc});
  final CarromOnlineController cc;

  @override
  Widget build(BuildContext context) {
    final GmView? v = cc.view;
    final CrMatch m = cc.match;
    final bool over = m.phase == CrPhase.finished || (v != null && !v.live);
    final int turn = v?.turn ?? m.turn;
    final TextDirection dir = cc.launch.isFa ? TextDirection.rtl : TextDirection.ltr;
    String status;
    if (over) {
      status = cc.launch.tx('پایان بازی', 'Game over');
    } else if (cc.replaying) {
      status = cc.launch.tx('ضربه‌ی ${cc.seatName(m.turn)}…', '${cc.seatName(m.turn)} shoots…');
    } else if (cc.submitting) {
      status = cc.launch.tx('ارسال ضربه…', 'Sending the shot…');
    } else if (m.phase == CrPhase.simulating) {
      status = '…';
    } else {
      status = cc.note.value;
    }
    final Color queenColor = m.queenCoveredBy >= 0
        ? kCrGold
        : (m.queenPendingFor >= 0 ? const Color(0xFFFF4F6E) : const Color(0x99EAF6FF));
    final String queenText = m.queenCoveredBy >= 0
        ? cc.launch.tx('ملکه: ', 'Queen: ') + (v?.nameOf(m.queenCoveredBy) ?? '')
        : (m.queenPendingFor >= 0 ? cc.launch.tx('ملکه منتظر پوشش', 'Queen awaiting cover') : cc.launch.tx('ملکه روی تخته', 'Queen on board'));
    Widget seat(int s) => KitPlayerHud(
          name: cc.seatName(s),
          subtitle: '${cc.launch.tx(s == 0 ? 'سفید' : 'مشکی', s == 0 ? 'White' : 'Black')} · '
              '${m.pocketedCount(s)}/${CrConfig.coinsPerSide}${m.queenCoveredBy == s ? ' ♛' : ''}',
          accent: s == 0 ? const Color(0xFF2EE6D6) : const Color(0xFFB57CFF),
          violet: s == 1,
          active: !over && turn == s,
          reducedMotion: cc.launch.reducedMotion,
          compact: true,
        );
    return Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
      Row(children: <Widget>[
        Expanded(child: seat(0)),
        const SizedBox(width: 8),
        Expanded(child: seat(1)),
      ]),
      const SizedBox(height: 4),
      Row(children: <Widget>[
        Icon(Icons.diamond_rounded, size: 13, color: queenColor),
        const SizedBox(width: 4),
        Flexible(
          child: Text(queenText,
              textDirection: dir,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: queenColor, fontSize: 11.5, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: Text(status,
              textAlign: TextAlign.center,
              textDirection: dir,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: turn == 0 ? kCrSeat0 : kCrSeat1, fontSize: 12.5, fontWeight: FontWeight.w700)),
        ),
      ]),
    ]);
  }
}

class _CarromOnlinePlacementBar extends StatelessWidget {
  const _CarromOnlinePlacementBar({required this.cc});
  final CarromOnlineController cc;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: cc,
      builder: (BuildContext context, Widget? _) {
        final bool enabled = cc.humanCanAim && !cc.aiming;
        final int seat = cc.match.turn;
        final Color col = cc.placementValid ? (seat == 0 ? kCrSeat0 : kCrSeat1) : kCrDanger;
        final double value = cc.strikerX.clamp(CrConfig.baseMinX, CrConfig.baseMaxX).toDouble();
        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
          child: Row(children: <Widget>[
            Icon(Icons.swap_horiz_rounded, size: 18, color: enabled ? col : const Color(0x55EAF6FF)),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: col.withOpacity(0.7),
                  inactiveTrackColor: col.withOpacity(0.2),
                  thumbColor: col,
                  overlayColor: col.withOpacity(0.15),
                  trackHeight: 3,
                ),
                child: Slider(
                  min: CrConfig.baseMinX,
                  max: CrConfig.baseMaxX,
                  value: value,
                  onChanged: enabled ? (double x) => cc.setPlacement(x) : null,
                ),
              ),
            ),
          ]),
        );
      },
    );
  }
}
