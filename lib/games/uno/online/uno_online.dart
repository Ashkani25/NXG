/// Online NX Cards (UNO-style, 2–6 real players). The server shuffles, deals and keeps the
/// draw pile secret; each player's hand is in their own private row (`view.private.hand`).
/// Moves: {a:'play', card, color?} {a:'draw'} {a:'pass'} {a:'nx'} {a:'catch'} (`_gm_uno_*`).
///
/// Wire state: top (card id), color (0..3 = turquoise, violet, gold, pink), dir, counts[], pile,
/// drawn (current player holds a playable drawn card), nx[], vul (seat that can be caught), last.
/// Card ids are exactly buildUnoDeck()'s ids.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:nexora/core/settings/app_settings.dart';
import 'package:nexora/core/theme/nx_theme.dart';
import 'package:nexora/games/core/online/gm_match_controller.dart';
import 'package:nexora/games/core/online/gm_models.dart';
import 'package:nexora/games/core/online/gm_widgets.dart';

import '../core/uno_models.dart';
import '../ui/uno_card_widget.dart';
import '../ui/uno_table_widgets.dart';

final List<UnoCard> kUnoDeck = buildUnoDeck();

UnoCard? unoCardById(int id) => id >= 0 && id < kUnoDeck.length ? kUnoDeck[id] : null;

UnoColor unoColorOf(int i) => UnoColor.values[i.clamp(0, UnoColor.values.length - 1)];

/// Same legality as `_gm_uno_legal` on the server (strict Wild Draw Four).
bool unoOnlineLegal(List<int> hand, int cardId, int topId, int activeColor) {
  final UnoCard? card = unoCardById(cardId);
  final UnoCard? top = unoCardById(topId);
  if (card == null) return false;
  if (card.isWild) {
    if (card.kind == UnoKind.wildDrawFour) {
      for (final int h in hand) {
        final UnoCard? c = unoCardById(h);
        if (c != null && h != cardId && !c.isWild && c.color!.index == activeColor) return false;
      }
    }
    return true;
  }
  if (card.color!.index == activeColor) return true;
  if (top == null || top.isWild) return false;
  return card.sameFace(top);
}

class UnoOnlineBoard extends StatefulWidget {
  const UnoOnlineBoard({super.key, required this.c});
  final GmMatchController c;

  @override
  State<UnoOnlineBoard> createState() => _UnoOnlineBoardState();
}

class _UnoOnlineBoardState extends State<UnoOnlineBoard> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  int? _wildPending;

  GmMatchController get c => widget.c;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _play(int id, {int? color}) async {
    HapticFeedback.selectionClick();
    final Map<String, dynamic> args = <String, dynamic>{'card': id};
    if (color != null) args['color'] = color;
    await c.move(GmMove('play', args));
  }

  @override
  Widget build(BuildContext context) {
    final GmView v = c.view!;
    final int? me = v.mySeat;
    final List<int> hand = gmInts(v.private['hand']);
    final int? drawn = gmIntOrNull(v.private['drawn']);
    final int top = gmInt(v.state['top']);
    final int color = gmInt(v.state['color']);
    final List<int> counts = gmInts(v.state['counts']);
    final List<bool> nx = gmBools(v.state['nx']);
    final int? vul = gmIntOrNull(v.state['vul']);
    final bool myTurn = v.myTurn;
    final Color accent = unoColorValue(unoColorOf(color));
    // opponents in play order, starting after me (spectators see every seat)
    final List<int> shownOthers = me == null
        ? <int>[for (int k = 0; k < v.seatCount; k++) k]
        : <int>[for (int k = 1; k < v.seatCount; k++) (me + k) % v.seatCount];
    final bool canNx = me != null &&
        v.live &&
        ((hand.length == 1 && vul == me) || (hand.length == 2 && myTurn && !(me < nx.length && nx[me])));
    final bool canCatch = v.live && me != null && vul != null && vul != me;
    return Stack(children: <Widget>[
      Positioned.fill(child: UnoTableBackground(fancy: true, accent: accent)),
      Column(children: <Widget>[
        SizedBox(
          height: 128,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: <Widget>[
              for (final int s in shownOthers)
                Opacity(
                  opacity: v.isOut(s) ? 0.35 : 1,
                  child: UnoSeatView(
                    name: v.nameOf(s),
                    cardCount: s < counts.length ? counts[s] : 0,
                    active: v.live && v.turn == s,
                    isBot: false,
                    nxSafe: s < nx.length && nx[s],
                    pulse: _pulse,
                    seatColor: gmSeatColor(s),
                    visible: true,
                  ),
                ),
            ],
          ),
        ),
        Expanded(child: _center(context, v, top, color, myTurn && drawn == null && !c.busy)),
        _status(context, v),
        if (me != null) _actions(context, v, drawn, canNx, canCatch),
        if (me != null) _hand(context, v, hand, drawn, top, color),
      ]),
      if (_wildPending != null)
        Positioned.fill(
          child: UnoColorPicker(
            isFa: context.isFa,
            onPick: (UnoColor col) {
              final int id = _wildPending!;
              setState(() => _wildPending = null);
              _play(id, color: col.index);
            },
            onCancel: () => setState(() => _wildPending = null),
          ),
        ),
    ]);
  }

  Widget _center(BuildContext context, GmView v, int top, int color, bool canDraw) {
    final UnoCard? topCard = unoCardById(top);
    final int dir = gmInt(v.state['dir'], 1);
    final UnoColor active = unoColorOf(color);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
          GestureDetector(
            onTap: canDraw ? () => c.move(const GmMove('draw')) : null,
            child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
              UnoCardView(width: 84, faceUp: false, glow: canDraw),
              const SizedBox(height: 4),
              Text(gmNum(context, gmInt(v.state['pile'])), style: const TextStyle(color: NxColors.textDim, fontSize: 12)),
            ]),
          ),
          const SizedBox(width: 28),
          Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              transitionBuilder: (Widget child, Animation<double> a) => ScaleTransition(scale: a, child: child),
              child: UnoCardView(
                key: ValueKey<int>(top),
                width: 96,
                card: topCard,
                wildColor: topCard != null && topCard.isWild ? active : null,
              ),
            ),
            const SizedBox(height: 6),
            Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
              Icon(dir == 1 ? Icons.rotate_right_rounded : Icons.rotate_left_rounded, color: unoColorValue(active)),
              const SizedBox(width: 4),
              Text(unoColorName(active, context.isFa), style: TextStyle(color: unoColorValue(active), fontWeight: FontWeight.w800)),
            ]),
          ]),
        ]),
      ),
    );
  }

  Widget _status(BuildContext context, GmView v) {
    if (!v.live) return const SizedBox(height: 8);
    final Map<String, dynamic> last = gmMap(v.state['last']);
    String msg = v.myTurn
        ? (v.state['drawn'] == true
            ? context.tx('کارت کشیده را بازی کن یا رد کن', 'Play the drawn card or pass')
            : context.tx('نوبت توست', 'Your turn'))
        : context.tx('نوبت ${v.nameOf(v.turn)}', "${v.nameOf(v.turn)}'s turn");
    final String who = v.nameOf(gmInt(last['seat']));
    switch ('${last['a'] ?? ''}') {
      case 'nx':
        msg += context.tx(' • $who گفت NX!', ' • $who called NX!');
        break;
      case 'catch':
        msg += context.tx(' • $who، ${v.nameOf(gmInt(last['victim']))} را گرفت (+۲)', ' • $who caught ${v.nameOf(gmInt(last['victim']))} (+2)');
        break;
      case 'draw':
        if (last['pass'] == true) msg += context.tx(' • $who کشید و رد کرد', ' • $who drew and passed');
        break;
      default:
        break;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Text(msg, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }

  Widget _actions(BuildContext context, GmView v, int? drawn, bool canNx, bool canCatch) {
    final List<Widget> b = <Widget>[];
    if (v.myTurn && drawn != null) {
      b.add(UnoActionButton(label: context.tx('رد کردن', 'Pass'), color: NxColors.violet, icon: Icons.skip_next_rounded, onTap: () => c.move(const GmMove('pass'))));
    }
    if (v.myTurn && drawn == null) {
      b.add(UnoActionButton(label: context.tx('کشیدن', 'Draw'), color: NxColors.electricBlue, icon: Icons.layers_rounded, onTap: () => c.move(const GmMove('draw'))));
    }
    if (canNx) {
      b.add(UnoActionButton(label: 'NX!', color: NxColors.gold, icon: Icons.campaign_rounded, onTap: () => c.move(const GmMove('nx'))));
    }
    if (canCatch) {
      b.add(UnoActionButton(label: context.tx('گرفتم!', 'Catch!'), color: NxColors.pink, icon: Icons.back_hand_rounded, onTap: () => c.move(const GmMove('catch'))));
    }
    if (b.isEmpty) return const SizedBox(height: 8);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Wrap(alignment: WrapAlignment.center, spacing: 10, runSpacing: 6, children: b),
    );
  }

  Widget _hand(BuildContext context, GmView v, List<int> hand, int? drawn, int top, int color) {
    final List<int> sorted = List<int>.from(hand)..sort();
    return SafeArea(
      top: false,
      child: SizedBox(
        height: 132,
        child: LayoutBuilder(builder: (BuildContext context, BoxConstraints bc) {
          const double w = 76;
          final int n = sorted.length;
          final double step = n <= 1 ? w : ((bc.maxWidth - w - 16) / (n - 1)).clamp(18.0, w + 6);
          final double total = n == 0 ? 0 : w + step * (n - 1);
          final double left0 = ((bc.maxWidth - total) / 2).clamp(8.0, double.infinity);
          return Directionality(
            textDirection: TextDirection.ltr,
            child: Stack(clipBehavior: Clip.none, children: <Widget>[
              for (int i = 0; i < n; i++)
                Builder(builder: (BuildContext context) {
                  final int id = sorted[i];
                  final bool legal = v.myTurn && !c.busy && (drawn == null || drawn == id) && unoOnlineLegal(hand, id, top, color);
                  return Positioned(
                    left: left0 + i * step,
                    top: legal ? 4 : 18,
                    child: GestureDetector(
                      onTap: legal
                          ? () {
                              final UnoCard? card = unoCardById(id);
                              if (card != null && card.isWild) {
                                setState(() => _wildPending = id);
                              } else {
                                _play(id);
                              }
                            }
                          : null,
                      child: UnoCardView(width: w, card: unoCardById(id), glow: legal, dim: v.myTurn && !legal),
                    ),
                  );
                }),
            ]),
          );
        }),
      ),
    );
  }
}

String? unoResultDetail(BuildContext context, GmView v) {
  final List<int> w = v.winners;
  if (w.length != 1 || v.reason != 'win') return null;
  final List<int> s = v.resultScores;
  final int pts = w.first < s.length ? s[w.first] : 0;
  return context.tx('امتیاز کارت‌های باقی‌مانده: ${gmNum(context, pts)}', 'Points from cards left: $pts');
}
