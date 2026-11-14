/// Online Disc Football match screen: [OnlineMatchNet] (pure netcode, Godot online_match.gd port) +
/// the shared renderer [DiscMatchView] + the online HUD (score board, clock, turn bar, whose turn,
/// ping, spectators, waiting overlay, goal banner, chat + voice, quit dialog).
/// Route: /online/match/:roomId/:matchId. Exits: result page (outcome as `extra`) or back to the lobby.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/settings/app_settings.dart';
import '../../../online/link.dart';
import '../../../online/models.dart';
import '../../../online/online_core.dart';
import '../../../online/supabase_client.dart';
import '../../../online/ui/oui.dart';
import '../../../online/ui/room_widgets.dart';
import '../core/engine.dart';
import '../ui/disc_match_view.dart';
import 'online_match_net.dart';

class OnlineMatchPage extends StatefulWidget {
  const OnlineMatchPage({super.key, required this.roomId, required this.matchId});
  final String roomId;
  final String matchId;

  @override
  State<OnlineMatchPage> createState() => _OnlineMatchPageState();
}

// ---------------------------------------------------------------- adapters
class _LinkAdapter implements MatchLink {
  _LinkAdapter(this.l);
  final RoomLink l;

  @override
  String get me => l.me;
  @override
  bool get connected => l.state.connected;
  @override
  bool isOnline(String uid) => l.state.online.containsKey(uid);
  @override
  int get onlineCount => l.state.online.length;
  @override
  String get currentHost => l.state.room?.host ?? '';
  @override
  List<NetPlayer> get players => <NetPlayer>[
        for (final RoomPlayer p in l.state.players)
          NetPlayer(userId: p.userId, role: p.role, team: p.team, slot: p.slot, disc: p.disc, name: p.profile?.username ?? ''),
      ];
  @override
  bool send(Map<String, dynamic> m) => l.sendGame(m);
  @override
  void ping() => l.ping();
  @override
  void refresh() => l.refresh();
}

class _Backend implements MatchBackend {
  _Backend(this.l);
  final RoomLink l;

  NetRes _n(OnlineResult r) => NetRes(r.ok, data: r.data, raw: r.raw);

  @override
  Future<NetRes> reportMatch(String matchId, int scoreA, int scoreB, int duration) async => _n(await callRpc(
      'report_match', <String, dynamic>{'p_match': matchId, 'p_score_a': scoreA, 'p_score_b': scoreB, 'p_duration': duration}));

  @override
  Future<NetRes> hostQuit(String matchId, List<int> score) async => _n(await l.hostQuit(matchId, score));

  @override
  Future<NetRes> claimHostLost(String matchId, List<int> score) async => _n(await l.claimHostLost(matchId, score));

  @override
  Future<Map<String, dynamic>?> fetchMatch(String matchId) async {
    final OnlineResult r = await guard(() => Online.client.from('matches').select('score_a,score_b,status').eq('id', matchId).maybeSingle());
    return r.ok && r.data is Map ? Map<String, dynamic>.from(r.data! as Map) : null;
  }
}

DiscStats _stats(String disc) {
  final ({double power, double accuracy}) s = discStatsOf(disc);
  return DiscStats(power: s.power, accuracy: s.accuracy);
}

// ---------------------------------------------------------------- screen
class _OnlineMatchPageState extends State<OnlineMatchPage> {
  final OnlineCore core = OnlineCore.instance;
  final DiscMatchController ctrl = DiscMatchController();
  final ValueNotifier<int> _hud = ValueNotifier<int>(0);
  RoomLink? link;
  OnlineMatchNet? net;
  StreamSubscription<double>? _resume;
  String _hudKey = '';
  bool _left = false;
  bool _quitOpen = false;
  bool _chatOpen = false;
  bool _wasMyTurn = false;
  int _lastTick = -1;
  int _goalMs = -100000;
  String _bannerT = '', _bannerS = '';
  Color _bannerC = OC.cyan;
  int _bannerId = 0;

  @override
  void initState() {
    super.initState();
    final RoomLink? l = core.linkForRoom(widget.roomId);
    link = l;
    if (l == null || l.state.room == null || widget.matchId.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        otoast(context, 'این مسابقه هنوز آماده نیست', err: true);
        _exit('aborted');
      });
      return;
    }
    core.skipMatch = widget.matchId;
    final Room room = l.state.room!;
    final OnlineMatchNet n = OnlineMatchNet(
      link: _LinkAdapter(l),
      backend: _Backend(l),
      matchId: widget.matchId,
      roomSettings: room.settings,
      roomHost: room.host,
      ranked: room.ranked,
      statsOf: _stats,
    );
    n.onEvent = _onEvent;
    n.onToast = (String m) {
      if (mounted) otoast(context, m, err: true);
    };
    n.onExit = (String why) {
      if (mounted) _exit(why);
    };
    n.onFinish = _finish;
    net = n;
    _cancelGame = l.onGame(n.onMsg);
    _resume = core.resumed.listen((_) => n.resumed());
    HapticFeedback.mediumImpact();
  }

  void Function()? _cancelGame;

  @override
  void dispose() {
    _cancelGame?.call();
    _resume?.cancel();
    net?.dispose();
    _hud.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- exits
  void _finish(NetOutcome o) {
    if (!mounted || _left) return;
    _left = true;
    core.skipMatch = widget.matchId;
    final OnlineOutcome out = OnlineOutcome(
      matchId: o.matchId,
      score: (o.score[0], o.score[1]),
      winner: o.winner,
      ratingDelta: o.ratingDelta,
      myTeam: o.myTeam,
      names: o.names,
      reported: o.reported,
      ranked: o.ranked,
      teams: o.teamIds,
    );
    context.pushReplacement('/online/result/${widget.roomId}', extra: out);
  }

  void _exit(String why) {
    if (!mounted || _left) return;
    _left = true;
    core.skipMatch = widget.matchId;
    link?.refresh();
    context.pushReplacement('/online/lobby/${widget.roomId}?skip=${widget.matchId}&why=$why');
  }

  // ---------------------------------------------------------------- events → feedback
  void _onEvent(EngineEvent ev) {
    ctrl.onEvent(ev);
    final OnlineMatchNet? n = net;
    if (n == null) return;
    switch (ev.t) {
      case 'hit':
        if (ev.power > 0.7) {
          HapticFeedback.mediumImpact();
        } else if (ev.power > 0.35) {
          HapticFeedback.lightImpact();
        }
      case 'post':
        HapticFeedback.mediumImpact();
      case 'shot':
        HapticFeedback.lightImpact();
      case 'goal':
        if (ev.nogoal) {
          _banner(context.tx('گل مردود', 'NO GOAL'), context.tx('با ضربه‌ی اول نمی‌شه گل زد', 'The kick-off shot can\'t score'), OC.dim);
        } else {
          final int ms = DateTime.now().millisecondsSinceEpoch;
          if (ms - _goalMs > 1200) {
            _goalMs = ms;
            HapticFeedback.heavyImpact();
          }
          _banner(context.tx('گل!', 'GOAL!'), n.names[ev.team], ev.team == 0 ? OC.cyan : OC.red);
        }
      case 'clock':
        _banner(context.tx('گل طلایی', 'GOLDEN GOAL'), context.tx('گل بعدی برنده‌ست', 'Next goal wins'), OC.gold);
      case 'end':
        HapticFeedback.heavyImpact();
      default:
        break;
    }
  }

  void _banner(String t, String s, Color c) {
    _bannerT = t;
    _bannerS = s;
    _bannerC = c;
    _bannerId++;
    _hud.value++;
  }

  // ---------------------------------------------------------------- frame
  void _onTick(double dt) {
    final OnlineMatchNet? n = net;
    if (n == null || _left) return;
    n.tick(dt);
    final Engine e = n.eng;
    final bool my = n.myTurn;
    if (my && !_wasMyTurn) HapticFeedback.mediumImpact();
    _wasMyTurn = my;
    if (n.ctrl == n.me && e.phase == Phase.aim && n.cfg.turnTime > 0) {
      final int sec = e.tleft.ceil();
      if (sec <= 3 && sec > 0 && sec != _lastTick) {
        _lastTick = sec;
        HapticFeedback.selectionClick();
      }
    } else {
      _lastTick = -1;
    }
    final String key =
        '${e.score[0]}:${e.score[1]}|${e.turn}|${e.mleft.ceil()}|${(e.tleft * 20).round()}|${e.sudden}|${n.ctrl}|${e.phase.name}|${n.waiting}|$my';
    if (key != _hudKey) {
      _hudKey = key;
      _hud.value++;
    }
  }

  void _pointer(Offset local, int kind) {
    final OnlineMatchNet? n = net;
    if (n == null || _quitOpen) return;
    final Offset w = ctrl.toWorld(local);
    if (kind == 0) {
      if (n.grant(w.dx, w.dy)) HapticFeedback.lightImpact();
    } else if (kind == 1) {
      n.move(w.dx, w.dy);
    } else if (kind == 2) {
      n.release();
    } else {
      n.terminate();
    }
  }

  String _nameOf(String uid) {
    if (uid.isEmpty) return context.tx('ربات', 'Bot');
    final RoomPlayer? p = link?.state.player(uid);
    final String n = p?.profile?.username ?? '';
    return n.isNotEmpty ? n : '…';
  }

  // ---------------------------------------------------------------- UI
  @override
  Widget build(BuildContext context) {
    final OnlineMatchNet? n = net;
    final RoomLink? l = link;
    if (n == null || l == null) return const Scaffold(backgroundColor: Color(0xFF050818), body: SizedBox.expand());
    final EdgeInsets pad = MediaQuery.of(context).padding;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool did, Object? _) {
        if (!did) setState(() => _quitOpen = !_quitOpen);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF050818),
        body: Stack(children: <Widget>[
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (PointerDownEvent e) => _pointer(e.localPosition, 0),
              onPointerMove: (PointerMoveEvent e) => _pointer(e.localPosition, 1),
              onPointerUp: (PointerUpEvent e) => _pointer(e.localPosition, 2),
              onPointerCancel: (PointerCancelEvent e) => _pointer(e.localPosition, 3),
              child: DiscMatchView(
                engine: n.eng,
                controller: ctrl,
                teamIds: n.teamIds,
                flipped: n.flipped,
                myTeam: n.myTeam,
                fancy: MediaQuery.of(context).disableAnimations ? false : true,
                topInset: pad.top + 120,
                bottomInset: pad.bottom + 84,
                onTick: _onTick,
              ),
            ),
          ),
          ValueListenableBuilder<int>(valueListenable: _hud, builder: (BuildContext context, int _, Widget? __) => _hudLayer(context, n, l, pad)),
          if (_chatOpen)
            Positioned(
              left: 12,
              right: 12,
              bottom: pad.bottom + 76,
              child: Material(
                color: const Color(0xF20A0F2C),
                borderRadius: BorderRadius.circular(20),
                child: Padding(padding: const EdgeInsets.only(top: 10), child: OChatPanel(l, compact: true)),
              ),
            ),
          if (_quitOpen) _quitLayer(context, n),
        ]),
      ),
    );
  }

  Widget _hudLayer(BuildContext context, OnlineMatchNet n, RoomLink l, EdgeInsets pad) {
    final Engine e = n.eng;
    final int s0 = e.score[0], s1 = e.score[1];
    final String clock = n.cfg.matchTime > 0
        ? (e.sudden ? context.tx('گل طلایی', 'Golden goal') : '${(e.mleft.ceil() < 0 ? 0 : e.mleft.ceil()) ~/ 60}:${((e.mleft.ceil() < 0 ? 0 : e.mleft.ceil()) % 60).toString().padLeft(2, '0')}')
        : context.tx('تا ${context.fn(n.cfg.limit)} گل', 'First to ${n.cfg.limit}');
    double tl = 1;
    if (n.cfg.turnTime > 0 && e.phase == Phase.aim) tl = (e.tleft / n.cfg.turnTime).clamp(0.0, 1.0).toDouble();
    final String c = n.ctrl;
    final bool myTurn = n.myTurn;
    final Color tc = e.turn == 0 ? OC.cyan : OC.red;
    final String turnText = e.phase == Phase.aim
        ? (c == n.me ? context.tx('نوبت توئه!', 'Your turn!') : context.tx('نوبت: ${_nameOf(c)}', 'Turn: ${_nameOf(c)}'))
        : (e.phase == Phase.goal ? context.tx('گل!', 'Goal!') : (e.phase == Phase.over ? context.tx('پایان بازی', 'Full time') : context.tx('در حال حرکت…', 'Moving…')));
    final int left = n.flipped ? 1 : 0;
    return Stack(children: <Widget>[
      // score board
      Positioned(
        top: pad.top + 8,
        left: 10,
        right: 10,
        child: Row(children: <Widget>[
          _roundBtn(Icons.close_rounded, () => setState(() => _quitOpen = true)),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 58,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(color: const Color(0xE0060A1E), borderRadius: BorderRadius.circular(18), border: Border.all(color: OC.cyan.withValues(alpha: .45))),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Row(children: <Widget>[
                  _side(n, left, e.turn == left, false),
                  Column(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
                    Text(n.flipped ? '$s1 : $s0' : '$s0 : $s1', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                    Text(clock, style: TextStyle(color: e.sudden ? OC.gold : OC.dim, fontSize: 10, fontWeight: FontWeight.w700)),
                  ]),
                  _side(n, 1 - left, e.turn == 1 - left, true),
                ]),
              ),
            ),
          ),
        ]),
      ),
      // turn timer + whose turn + ping / spectators
      Positioned(
        top: pad.top + 72,
        left: 60,
        right: 16,
        child: Column(children: <Widget>[
          if (n.cfg.turnTime > 0)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Container(
                height: 5,
                color: const Color(0x14FFFFFF),
                alignment: AlignmentDirectional.centerStart,
                child: FractionallySizedBox(widthFactor: tl, child: Container(color: tc)),
              ),
            ),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: myTurn ? tc.withValues(alpha: .2) : const Color(0xD9060A1E),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: tc.withValues(alpha: .67), width: 1.5),
              ),
              child: Text(turnText, style: TextStyle(color: myTurn ? Colors.white : OC.text, fontWeight: FontWeight.w900, fontSize: 13)),
            ),
            const SizedBox(width: 8),
            if (n.myTeam < 0)
              ListenableBuilder(
                listenable: l,
                builder: (BuildContext context, _) {
                  final int specs = l.state.players.where((RoomPlayer p) => p.role == 'spectator' && l.state.online.containsKey(p.userId)).length;
                  return OBadge(context.tx('زنده · ${context.fn(specs)} تماشاگر', 'Live · ${context.fn(specs)} watching'), color: OC.red, live: true);
                },
              ),
            if (!n.isHost) OPingBadge(l),
          ]),
        ]),
      ),
      // goal / golden-goal banner
      if (_bannerT.isNotEmpty)
        Positioned.fill(
          child: IgnorePointer(
            child: Align(
              alignment: const Alignment(0, -.15),
              child: TweenAnimationBuilder<double>(
                key: ValueKey<int>(_bannerId),
                tween: Tween<double>(begin: 0, end: 1),
                duration: const Duration(milliseconds: 1900),
                builder: (BuildContext context, double k, Widget? child) {
                  final double s = k < .25 ? .3 + Curves.easeOutBack.transform(k / .25) * .7 : (k > .8 ? 1 + (k - .8) * 1.25 : 1);
                  final double a = k < .06 ? k / .06 : (k > .8 ? (1 - (k - .8) / .2) : 1);
                  return Opacity(opacity: a.clamp(0.0, 1.0).toDouble(), child: Transform.scale(scale: s, child: child));
                },
                child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                  Text(_bannerT, style: TextStyle(color: Colors.white, fontSize: 56, fontWeight: FontWeight.w900, shadows: <Shadow>[Shadow(color: _bannerC, blurRadius: 24)])),
                  if (_bannerS.isNotEmpty) Text(_bannerS, style: TextStyle(color: _bannerC, fontSize: 16, fontWeight: FontWeight.w800)),
                ]),
              ),
            ),
          ),
        ),
      // waiting overlay
      if (n.waiting)
        Positioned.fill(
          child: IgnorePointer(
            child: Container(
              color: const Color(0xB8020410),
              alignment: Alignment.center,
              child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                const SizedBox(width: 34, height: 34, child: CircularProgressIndicator(color: OC.cyan, strokeWidth: 3)),
                const SizedBox(height: 14),
                Text(context.tx('در حال اتصال به میزبان…', 'Connecting to the host…'), style: const TextStyle(color: OC.text, fontSize: 16, fontWeight: FontWeight.w800)),
              ]),
            ),
          ),
        ),
      // chat + voice
      Positioned(
        left: 14,
        bottom: pad.bottom + 12,
        child: ListenableBuilder(
          listenable: l,
          builder: (BuildContext context, _) => Row(children: <Widget>[
            Stack(clipBehavior: Clip.none, children: <Widget>[
              _roundBtn(Icons.forum_rounded, () {
                setState(() => _chatOpen = !_chatOpen);
                if (_chatOpen) l.markRead();
              }),
              if (l.state.unread > 0 && !_chatOpen)
                Positioned(
                  top: -4,
                  right: -4,
                  child: CircleAvatar(radius: 10, backgroundColor: OC.red, child: Text(context.fn(l.state.unread > 9 ? 9 : l.state.unread), style: const TextStyle(color: Colors.white, fontSize: 10))),
                ),
            ]),
            const SizedBox(width: 10),
            if (l.state.room?.voice ?? false) OVoiceBar(l, compact: true),
          ]),
        ),
      ),
    ]);
  }

  Widget _side(OnlineMatchNet n, int t, bool on, bool right) {
    final Color col = t == 0 ? OC.cyan : OC.red;
    final List<Widget> kids = <Widget>[
      Container(
        decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: on ? <BoxShadow>[BoxShadow(color: col.withValues(alpha: .8), blurRadius: 12)] : null),
        child: OAvatar(disc: n.teamIds[t], size: 40, ring: on ? col : const Color(0x26FFFFFF)),
      ),
      const SizedBox(width: 6),
      Expanded(
        child: Text(n.names[t],
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: right ? TextAlign.right : TextAlign.left,
            style: TextStyle(color: on ? Colors.white : OC.dim, fontSize: 12, fontWeight: FontWeight.w800)),
      ),
    ];
    return Expanded(child: Row(children: right ? kids.reversed.toList() : kids));
  }

  Widget _roundBtn(IconData i, VoidCallback f) => InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: f,
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(color: const Color(0xE0080C22), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0x33FFFFFF))),
          child: Icon(i, color: OC.text),
        ),
      );

  Widget _quitLayer(BuildContext context, OnlineMatchNet n) {
    final String msg = n.isHost
        ? context.tx('تو میزبانی؛ با خروج تو بازی برای همه لغو می‌شود.', 'You are the host; leaving ends the match for everyone.')
        : (n.myTeam < 0
            ? context.tx('تماشای بازی را ترک می‌کنی.', 'You stop watching the match.')
            : context.tx('بازی بدون تو ادامه پیدا می‌کند و ربات جای تو بازی می‌کند.', 'The match continues without you and the bot plays for you.'));
    return Positioned.fill(
      child: Container(
        color: const Color(0xB8020410),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(28),
        child: OPanel(
          accent: OC.cyan,
          glow: true,
          pad: 20,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
            Text(context.tx('خروج از بازی؟', 'Leave the match?'),
                textAlign: TextAlign.center, style: const TextStyle(color: OC.text, fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            Text(msg, textAlign: TextAlign.center, style: const TextStyle(color: OC.dim, fontSize: 13)),
            const SizedBox(height: 16),
            OBtn(context.tx('ادامه‌ی بازی', 'Keep playing'), onTap: () => setState(() => _quitOpen = false)),
            const SizedBox(height: 8),
            OBtn(context.tx('خروج', 'Leave'), small: true, style: OBtnStyle.red, onTap: () {
              setState(() => _quitOpen = false);
              n.quit();
            }),
          ]),
        ),
      ),
    );
  }
}
