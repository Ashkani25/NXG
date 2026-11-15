// v0.7.0 pre-match lineup (cup games): opened by pressing Play in the cup room. A 30-second countdown (never longer,
// shortened to the server's lineup_until) to pick team and formation; the room host also picks the pitch and ball,
// which the server applies to BOTH sides. Every change is saved server-side through cup_ready (team_id, formation,
// field, ball); the first press opens the server window, both players ready starts the game at once, and when the
// timer runs out whatever is selected (or the defaults: equipped team, formation 0, room pitch/ball) is used.
import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../core/assets.dart';
import '../core/owned.dart';
import '../core/sound.dart';
import '../core/store.dart';
import '../core/theme.dart';
import '../game/data.dart';
import '../net/supabase.dart';
import '../screens/formation_sheet.dart';
import '../ui/chrome.dart';
import '../ui/kit.dart';
import 'cup_logic.dart';
import 'lobby.dart' show FieldPicker;

/// Sends one cup_ready call; returns the server reply ({now, lineup_until, status, ready, ...}).
typedef CupReadySend = Future<Map<String, dynamic>> Function(Map<String, Object?> params);

Future<Map<String, dynamic>> cupReadyRpc(Map<String, Object?> p) async {
  final r = await rpc('cup_ready', p);
  return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
}

class CupLineupScreen extends StatefulWidget {
  final String matchId;
  final bool isHost;
  final int roomField, roomBall;
  final DateTime? serverUntil;
  final CupReadySend send;
  final DateTime Function() clock;
  final void Function(bool started) onDone;
  const CupLineupScreen({super.key, required this.matchId, required this.isHost, required this.roomField, required this.roomBall, this.serverUntil,
      this.send = cupReadyRpc, this.clock = _now, required this.onDone});
  static DateTime _now() => DateTime.now().toUtc();
  @override
  State<CupLineupScreen> createState() => CupLineupScreenState();
}

class CupLineupScreenState extends State<CupLineupScreen> {
  late final DateTime pressedAt = widget.clock();
  DateTime? serverUntil;
  String? team;
  int? form, field, ball;
  int secs = kCupLineupSeconds, sends = 0;
  bool sentFinal = false, closed = false;
  Timer? _t, _debounce;

  @override
  void initState() {
    super.initState();
    serverUntil = widget.serverUntil;
    team = Store.i.p.team;
    form = Store.i.p.form;
    if (widget.isHost) {
      field = widget.roomField;
      ball = widget.roomBall;
    }
    _send(); // the press itself: opens the server's 30 s window with the current (default) selection
    _t = Timer.periodic(const Duration(milliseconds: 200), (_) => _tick());
  }

  @override
  void dispose() {
    _t?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  Map<String, Object?> get params => {
        'p_match': widget.matchId,
        'p_team': team,
        'p_formation': form ?? 0,
        'p_field': widget.isHost ? field : null,
        'p_ball': widget.isHost ? ball : null,
      };

  Future<void> _send() async {
    sends++;
    try {
      final r = await widget.send(params);
      final u = DateTime.tryParse('${r['lineup_until'] ?? ''}')?.toUtc();
      if (u != null && mounted) setState(() => serverUntil = u);
      if ('${r['status']}' == 'live') _close(true);
    } catch (e) {
      if (mounted && !sentFinal) toast(errFa(e), 'err');
    }
  }

  void _changed() {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _send);
  }

  void _tick() {
    if (!mounted || closed) return;
    final s = lineupSecondsLeft(now: widget.clock(), pressedAt: pressedAt, serverUntil: serverUntil);
    if (s != secs) {
      setState(() => secs = s);
      if (s > 0 && s <= 5) sfx(Snd.tick);
    }
    // a second before the end the final selection goes out, so the server never starts on stale picks
    if (s <= 1 && !sentFinal) finish();
  }

  /// "Ready" pressed, or the timer ran out: send the final lineup and close.
  Future<void> finish() async {
    if (sentFinal) return;
    sentFinal = true;
    _debounce?.cancel();
    await _send();
    _close(false);
  }

  void _close(bool started) {
    if (closed) return;
    closed = true;
    _t?.cancel();
    widget.onDone(started);
  }

  @override
  Widget build(BuildContext context) {
    final k = secs / kCupLineupSeconds;
    final teams = kTeams.where((t) => ownsTeam(t.id)).toList();
    return Scaffold(
      backgroundColor: const Color(0xf2050a26),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
          Row(textDirection: TextDirection.rtl, children: [
            const NxIcon(Icons.groups_rounded, color: C.orange, size: 36),
            const SizedBox(width: 10),
            Expanded(child: tTitle('آماده‌سازی مسابقه', size: 20, align: TextAlign.right)),
            SizedBox(
              key: const ValueKey('lineupTimer'),
              width: 64,
              height: 64,
              child: Stack(alignment: Alignment.center, children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: k, end: k),
                  duration: const Duration(milliseconds: 200),
                  builder: (_, v, _) => CircularProgressIndicator(value: v, strokeWidth: 5, color: secs <= 5 ? C.red : C.orange, backgroundColor: const Color(0x22ffffff)),
                ),
                tTitle(fa(secs), size: 22, color: secs <= 5 ? C.red : C.text),
              ]),
            ),
          ]),
          const SizedBox(height: 4),
          T('حداکثر ${fa(kCupLineupSeconds)} ثانیه؛ بعد از آن انتخاب فعلی (یا پیش‌فرض) استفاده می‌شود.', size: 11, color: C.dim, align: TextAlign.right),
          const SizedBox(height: 14),
          tBold('تیم', size: 13, color: C.cyan, align: TextAlign.right),
          const SizedBox(height: 6),
          SizedBox(
            height: 66,
            child: ListView(scrollDirection: Axis.horizontal, reverse: true, children: [
              for (final t in teams)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Press(
                    onTap: () {
                      team = t.id;
                      Store.i.set((p) => p.team = t.id);
                      _changed();
                    },
                    child: AnimatedScale(scale: t.id == team ? 1.1 : 1, duration: const Duration(milliseconds: 260), curve: Curves.easeOutBack, child: Disc(teamImg(t), size: 54, ring: t.id == team ? C.cyan : C.line)),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 14),
          tBold('ترکیب', size: 13, color: C.cyan, align: TextAlign.right),
          const SizedBox(height: 6),
          SizedBox(
            height: 92,
            child: ListView(scrollDirection: Axis.horizontal, reverse: true, children: [
              for (var i = 0; i < kForms.length; i++)
                Press(
                  key: ValueKey('lineupForm$i'),
                  onTap: () {
                    form = i;
                    Store.i.set((p) => p.form = i);
                    _changed();
                  },
                  child: Container(
                    width: 58,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(children: [
                      Expanded(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: form == i ? C.cyan : const Color(0x33ffffff), width: form == i ? 2.4 : 1)),
                          clipBehavior: Clip.antiAlias,
                          child: CustomPaint(painter: MiniFormationPainter(i), child: const SizedBox.expand()),
                        ),
                      ),
                      const SizedBox(height: 3),
                      T(kForms[i].code, size: 10, color: form == i ? C.cyan : C.dim),
                    ]),
                  ),
                ),
            ]),
          ),
          if (widget.isHost) ...[
            const SizedBox(height: 14),
            Panel(
              accent: C.violet,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                tBold('میزبان: زمین و توپ برای هر دو طرف', size: 12, color: C.violet, align: TextAlign.right),
                const SizedBox(height: 8),
                FieldPicker(value: (field ?? widget.roomField).clamp(0, kFields.length - 1), onChange: (v) {
                  field = v;
                  _changed();
                }),
                const SizedBox(height: 6),
                SizedBox(
                  height: 52,
                  child: ListView(scrollDirection: Axis.horizontal, reverse: true, children: [
                    for (var i = 0; i < 36; i++)
                      Press(
                        key: ValueKey('lineupBall$i'),
                        onTap: () {
                          ball = i;
                          _changed();
                        },
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ball == i ? C.cyan : C.line, width: ball == i ? 2 : 1)),
                          child: Img(ballImg(i), w: 40, h: 40, fit: BoxFit.contain),
                        ),
                      ),
                  ]),
                ),
              ]),
            ),
          ],
          const SizedBox(height: 18),
          Btn(sentFinal ? '…' : 'آماده‌ام', key: const ValueKey('lineupReady'), colors: G.green, onTap: sentFinal ? null : finish),
        ]),
      ),
    );
  }
}
