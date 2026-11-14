import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:nexora/core/assets/app_assets.dart';
import 'package:nexora/games/core/game_contract.dart';
import 'package:nexora/games/kit_v2/ui/kit_v2_widgets.dart';
import '../core/carrom_config.dart';
import '../core/carrom_match.dart';
import 'cr_controller.dart';
import 'cr_fx.dart';
import 'cr_painter.dart';

const String _kRulesFa = 'هدف: هر ۹ مهره‌ی رنگ خودت را (سفید برای پایین، مشکی برای بالا) به چاله‌ها بینداز و ملکه‌ی قرمز را پوشش بده.\n\n'
    '• استرایکر را با اسلایدر روی خط پایه جابه‌جا کن، سپس روی صفحه بکش و رها کن؛ هرچه بیشتر بکشی ضربه قوی‌تر است.\n'
    '• اگر مهره‌ی خودت یا ملکه را بیندازی دوباره نوبت توست.\n'
    '• ملکه: بعد از انداختنش باید در همان ضربه یا ضربه‌ی بعد یک مهره‌ی خودی بیندازی (پوشش)، وگرنه ملکه به مرکز برمی‌گردد. ملکه‌ی پوشش‌داده‌شده ۳ امتیاز دارد.\n'
    '• خطا: افتادن استرایکر؛ مهره‌های خودی همان ضربه و یکی از مهره‌های قبلی‌ات برمی‌گردند و نوبت تمام می‌شود.\n'
    '• مهره‌ی حریف که بیندازی برای حریف حساب می‌شود.\n'
    '• آخرین مهره‌ی یک رنگ قبل از پوشش ملکه مجاز نیست و برمی‌گردد.\n'
    '• هر نوبت ۳۰ ثانیه وقت دارد.';

const String _kRulesEn = 'Goal: pocket all 9 coins of your colour (white for the bottom player, black for the top) and cover the red queen.\n\n'
    '• Slide the striker along your baseline with the slider, then drag on the board and release — the longer the pull, the harder the shot.\n'
    '• Pocket one of your coins or the queen and you shoot again.\n'
    '• Queen: after pocketing it you must pocket one of your own coins in the same or next shot (cover it), otherwise it returns to the centre. A covered queen is worth 3 points.\n'
    '• Foul: pocketing the striker. Your coins from that shot plus one already-pocketed coin return, and your turn ends.\n'
    '• Opponent coins you pocket count for the opponent.\n'
    '• Your last coin cannot go down before the queen is covered — it is returned.\n'
    '• Each turn has a 30-second timer.';

/// Full-screen Carrom match (the host provides Scaffold, exit button and result screen).
class CarromView extends StatefulWidget {
  const CarromView({super.key, required this.launch});
  final GameLaunch launch;

  @override
  State<CarromView> createState() => _CarromViewState();
}

class _CarromViewState extends State<CarromView> with SingleTickerProviderStateMixin {
  late final CrController _c;
  late final Ticker _ticker;
  final CrImages _images = CrImages();
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _c = CrController(widget.launch);
    _ticker = createTicker(_onTick);
    _ticker.start();
    _loadImages();
  }

  Future<void> _loadImages() async {
    // kit_v2 art first; the classic NX art is the fallback, then procedural.
    ui.Image? board = await crLoadImage(AppAssets.kitV2BoardsBoardCarrom, 1024);
    final bool kitBoard = board != null;
    board ??= await crLoadImage(AppAssets.gamesCarromBoardNxBlackGold, 1024);
    final ui.Image? white = await crLoadImage(AppAssets.kitV2PiecesCoinWhite1, 96) ??
        await crLoadImage(AppAssets.gamesSharedDiscsDiscCream, 96);
    final ui.Image? black = await crLoadImage(AppAssets.kitV2PiecesCoinDark1, 96) ??
        await crLoadImage(AppAssets.gamesSharedDiscsDiscBlack, 96);
    final ui.Image? queen = await crLoadImage(AppAssets.kitV2PiecesCoinQueen, 96) ??
        await crLoadImage(AppAssets.disc('disc_red'), 96);
    // An equipped catalog striker stays the player's own; otherwise kit strikers.
    final bool equipped = widget.launch.skins['striker'] != null;
    final ui.Image? s0 = (equipped ? null : await crLoadImage(AppAssets.kitV2PiecesStrikerCyan, 128)) ??
        await crLoadImage(AppAssets.disc(_c.strikerSkin0), 128);
    final ui.Image? s1 = await crLoadImage(AppAssets.kitV2PiecesStrikerSilver, 128) ??
        await crLoadImage(AppAssets.disc(_c.strikerSkin1), 128);
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
    var dt = (elapsed - _last).inMicroseconds / 1000000.0;
    _last = elapsed;
    if (dt < 0) dt = 0;
    if (dt > 0.05) dt = 0.05;
    _c.tick(dt);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _c.dispose();
    super.dispose();
  }

  void _showRules() {
    final launch = widget.launch;
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) {
        return Directionality(
          textDirection: launch.isFa ? TextDirection.rtl : TextDirection.ltr,
          child: AlertDialog(
            backgroundColor: const Color(0xF20B1230),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Color(0x66FFC857)),
            ),
            title: Text(
              launch.tx('قوانین کارم', 'Carrom rules'),
              style: const TextStyle(color: kCrGold, fontWeight: FontWeight.w800),
            ),
            content: SingleChildScrollView(
              child: Text(
                launch.tx(_kRulesFa, _kRulesEn),
                style: const TextStyle(color: Color(0xFFEAF6FF), fontSize: 14, height: 1.55),
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(launch.tx('فهمیدم', 'Got it'), style: const TextStyle(color: kCrGold)),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final launch = widget.launch;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        type: MaterialType.transparency,
        child: DecoratedBox(
          decoration: const BoxDecoration(color: Color(0xFF04050F)),
          child: Stack(
            children: <Widget>[
              const Positioned.fill(child: IgnorePointer(child: KitRoomBackground())),
              SafeArea(
                child: Column(
                  children: <Widget>[
                    // Top bar keeps 64px free on both sides (host exit button sits top-start, LTR or RTL).
                    Padding(
                      padding: const EdgeInsets.fromLTRB(64, 6, 64, 0),
                      child: ValueListenableBuilder<CrHudData>(
                        valueListenable: _c.hud,
                        builder: (BuildContext context, CrHudData h, Widget? _) =>
                            _CrHud(hud: h, c: _c, launch: launch, onRules: _showRules),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        child: LayoutBuilder(
                          builder: (BuildContext context, BoxConstraints cons) {
                            _c.viewSize = Size(cons.maxWidth, cons.maxHeight);
                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onPanStart: (DragStartDetails d) => _c.onPanStart(d.localPosition),
                              onPanUpdate: (DragUpdateDetails d) => _c.onPanUpdate(d.localPosition),
                              onPanEnd: (DragEndDetails d) => _c.onPanEnd(),
                              onPanCancel: _c.onPanCancel,
                              child: CustomPaint(
                                size: Size(cons.maxWidth, cons.maxHeight),
                                painter: CrPainter(_c, _images),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    _CrPlacementBar(c: _c, launch: launch),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class _CrHud extends StatelessWidget {
  const _CrHud({required this.hud, required this.c, required this.launch, required this.onRules});
  final CrHudData hud;
  final CrController c;
  final GameLaunch launch;
  final VoidCallback onRules;

  String _queenText() {
    if (hud.queenCoveredBy >= 0) {
      return launch.tx('ملکه: ', 'Queen: ') + c.seatName(hud.queenCoveredBy);
    }
    if (hud.queenPendingFor >= 0) {
      return launch.tx('ملکه منتظر پوشش', 'Queen awaiting cover');
    }
    return launch.tx('ملکه روی تخته', 'Queen on board');
  }

  @override
  Widget build(BuildContext context) {
    final finished = hud.phase == CrPhase.finished;
    final turnColor = hud.turn == 0 ? kCrSeat0 : kCrSeat1;
    String status;
    if (finished) {
      status = launch.tx('پایان بازی', 'Game over');
    } else if (hud.botThinking) {
      status = launch.tx('ربات فکر می‌کند…', 'Bot is thinking…');
    } else if (hud.phase == CrPhase.simulating) {
      status = launch.tx('…', '…');
    } else if (launch.vsBot) {
      status = hud.turn == 0 ? launch.tx('نوبت شما', 'Your turn') : launch.tx('نوبت ربات', 'Bot\'s turn');
    } else {
      status = launch.tx('نوبت ', 'Turn: ') + c.seatName(hud.turn);
    }
    final double timerValue = (hud.timeLeft / CrConfig.turnSeconds).clamp(0.0, 1.0).toDouble();
    final Color timerColor = hud.timeLeft <= 5 ? kCrDanger : turnColor;
    final TextDirection textDir = launch.isFa ? TextDirection.rtl : TextDirection.ltr;
    final queenColor = hud.queenCoveredBy >= 0
        ? kCrGold
        : (hud.queenPendingFor >= 0 ? const Color(0xFFFF4F6E) : const Color(0x99EAF6FF));

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0x2215183A),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0x44FFC857)),
            boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x33000000), blurRadius: 14)],
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: KitPlayerHud(
                  name: c.seatName(0),
                  subtitle: '${launch.tx('مهره', 'Coins')} ${hud.pocketed0}/${CrConfig.coinsPerSide}'
                      '${hud.queenCoveredBy == 0 ? ' ♛' : ''}',
                  accent: const Color(0xFF2EE6D6),
                  violet: false,
                  active: !finished && hud.turn == 0,
                  reducedMotion: launch.reducedMotion,
                  compact: true,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: SizedBox(
                  width: 46,
                  height: 46,
                  child: Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      SizedBox(
                        width: 46,
                        height: 46,
                        child: CircularProgressIndicator(
                          value: finished ? 0 : timerValue,
                          strokeWidth: 4,
                          backgroundColor: const Color(0x22FFFFFF),
                          valueColor: AlwaysStoppedAnimation<Color>(timerColor),
                        ),
                      ),
                      Text(
                        finished ? '–' : '${hud.timeLeft}',
                        style: TextStyle(color: timerColor, fontWeight: FontWeight.w800, fontSize: 15),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: KitPlayerHud(
                  name: c.seatName(1),
                  subtitle: '${launch.tx('مهره', 'Coins')} ${hud.pocketed1}/${CrConfig.coinsPerSide}'
                      '${hud.queenCoveredBy == 1 ? ' ♛' : ''}',
                  accent: const Color(0xFFB57CFF),
                  violet: true,
                  active: !finished && hud.turn == 1,
                  reducedMotion: launch.reducedMotion,
                  compact: true,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: queenColor.withOpacity(0.6)),
                color: queenColor.withOpacity(0.10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.diamond_rounded, size: 13, color: queenColor),
                  const SizedBox(width: 4),
                  Text(_queenText(), textDirection: textDir, style: TextStyle(color: queenColor, fontSize: 11.5, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: Text(
                  hud.toast.isNotEmpty ? hud.toast : status,
                  key: ValueKey<String>(hud.toast.isNotEmpty ? hud.toast : status),
                  textAlign: TextAlign.center,
                  textDirection: textDir,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: hud.toast.isNotEmpty ? hud.toastColor : turnColor,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            InkWell(
              onTap: onRules,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0x66FFC857)),
                  color: const Color(0x22FFC857),
                ),
                child: const Icon(Icons.menu_book_rounded, size: 16, color: kCrGold),
              ),
            ),
          ],
        ),
      ],
    );
  }
}


/// Striker placement slider (enabled only while the local human can aim).
class _CrPlacementBar extends StatelessWidget {
  const _CrPlacementBar({required this.c, required this.launch});
  final CrController c;
  final GameLaunch launch;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: c,
      builder: (BuildContext context, Widget? _) {
        final enabled = c.humanCanAim && !c.aiming;
        final seat = c.match.turn;
        final col = c.placementValid ? (seat == 0 ? kCrSeat0 : kCrSeat1) : kCrDanger;
        final value = c.strikerX.clamp(CrConfig.baseMinX, CrConfig.baseMaxX).toDouble();
        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
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
                        onChanged: enabled ? (double v) => c.setPlacement(v) : null,
                      ),
                    ),
                  ),
                ],
              ),
              Text(
                enabled
                    ? launch.tx('استرایکر را جابه‌جا کن، سپس روی تخته بکش و رها کن', 'Slide the striker, then drag on the board and release')
                    : (c.isBotTurn ? launch.tx('ربات در حال بازی…', 'Bot is playing…') : ' '),
                textAlign: TextAlign.center,
                textDirection: launch.isFa ? TextDirection.rtl : TextDirection.ltr,
                style: const TextStyle(color: Color(0x99EAF6FF), fontSize: 11.5),
              ),
            ],
          ),
        );
      },
    );
  }
}
