// Online match netcode for Disc Football — pure Dart port of the Godot app's
// src/online/online_match.gd (itself a hardened port of Expo OnlineMatch.tsx). No Flutter imports.
//
//  HOST   runs the real simulation (Engine.update) at display rate, applies remote shot inputs and
//         broadcasts compact snapshots: 20–30 Hz while anything moves, 2 Hz at rest, immediately on
//         events (shot, goal, turn, clock, end). Events ride inside snapshots.
//  OTHERS (players + spectators) never simulate: they buffer snapshots, estimate the host clock offset
//         and render ~1.7 snapshot intervals in the past, interpolating every disc + ball (120 ms
//         extrapolation when starved). Events fire when playback reaches them.
//
//  CONTROL RULE (2v2 / 3v3): turns alternate between teams. Within a team the humans rotate: the k-th
//  turn of team T belongs to slot (k-1) mod teamSize. A disconnected player is skipped; a team with
//  nobody connected is played by the bot (AI takeover). The controller may flick ANY disc of their team
//  and flicks with their own equipped disc's stats.
//
//  Hardening (same as Godot): every game message carries the match id `mid` (stale messages from an
//  earlier match in the same room are dropped), duplicate / out-of-order snapshots are dropped / sorted,
//  shot requests are resent (same seq, host dedupes by seq + phase) if no ack arrives, host absence is
//  detected from presence + snapshot silence (claim_host_lost), the host forfeits / abandons cleanly on
//  quit / screen exit (host_forfeit → abandon_match).
import 'dart:async';
import 'dart:math' as math;

import '../core/data.dart';
import '../core/engine.dart';
import '../core/net_codec.dart';

const double kOnlineLmax = 210.0;
const double kHostSilence = 8.0;
const double kFirstSnapWait = 12.0;

/// after kHostSilence we ask the server to settle (it agrees once the host is 30 s silent there);
/// give up and go back to the lobby after this much total silence
const double kHostGiveUp = 60.0;

/// our own link may be down this long before we give up (the host keeps simulating meanwhile)
const double kSelfOfflineGiveUp = 45.0;

/// A room player as the netcode needs it (adapter over RoomPlayer).
class NetPlayer {
  const NetPlayer({required this.userId, required this.role, this.team, this.slot, this.disc = 'club0', this.name = ''});
  final String userId;
  final String role;
  final int? team;
  final int? slot;

  /// disc shown / used for stats (disc_id → equipped_disc → avatar → club0)
  final String disc;
  final String name;
}

/// What the netcode needs from the RoomLink.
abstract class MatchLink {
  String get me;
  bool get connected;
  bool isOnline(String uid);
  int get onlineCount;

  /// current room host (may change after claim_host_lost)
  String get currentHost;
  List<NetPlayer> get players;

  /// broadcast a 'g' message (the link adds from + gi); false when not sent
  bool send(Map<String, dynamic> m);
  void ping();
  void refresh();
}

/// Result of a backend call (never throws).
class NetRes {
  const NetRes(this.ok, {this.data, this.raw = ''});
  final bool ok;
  final Object? data;
  final String raw;
  Map<String, dynamic> get map => data is Map ? Map<String, dynamic>.from(data! as Map) : <String, dynamic>{};
}

/// Server side of the match (report_match, host_forfeit/abandon, claim_host_lost, matches row).
abstract class MatchBackend {
  Future<NetRes> reportMatch(String matchId, int scoreA, int scoreB, int duration);
  Future<NetRes> hostQuit(String matchId, List<int> score);
  Future<NetRes> claimHostLost(String matchId, List<int> score);

  /// matches row {score_a, score_b, status} or null
  Future<Map<String, dynamic>?> fetchMatch(String matchId);
}

/// Outcome dict of online_match.gd: {match_id, score, winner, rating_delta, my_team, team_ids, names, reported, ranked}.
class NetOutcome {
  const NetOutcome({
    required this.matchId,
    required this.score,
    required this.winner,
    required this.ratingDelta,
    required this.myTeam,
    required this.teamIds,
    required this.names,
    required this.reported,
    required this.ranked,
  });
  final String matchId;
  final List<int> score;

  /// -1 draw, 0 blue, 1 red
  final int winner;
  final int? ratingDelta;

  /// null = spectator
  final int? myTeam;
  final List<String> teamIds;
  final List<String> names;
  final bool reported;
  final bool ranked;
}

enum NetDone { no, ended, finished, aborted }

int _ni(Object? v, [int d = 0]) => v is num ? v.toInt() : (v is String ? (int.tryParse(v) ?? (double.tryParse(v)?.toInt() ?? d)) : d);
double _nd(Object? v, [double d = 0]) => v is num ? v.toDouble() : (v is String ? (double.tryParse(v) ?? d) : d);

/// players of team t sorted by slot (online_match.gd team_of)
List<NetPlayer> teamOf(List<NetPlayer> players, int t) {
  final List<NetPlayer> out = players.where((NetPlayer p) => p.role == 'player' && p.team == t).toList();
  out.sort((NetPlayer a, NetPlayer b) => (a.slot ?? 0).compareTo(b.slot ?? 0));
  return out;
}

/// A buffered snapshot (raw wire map + parsed values).
class _Buf {
  _Buf(this.q, this.ts, this.hz, this.s);
  final int q;
  final double ts;
  final int hz;
  final Snap s;
}

class _PendingShot {
  _PendingShot(this.msg, this.n, this.at);
  final Map<String, dynamic> msg;
  final int n;
  double at;
  int tries = 0;
}

class OnlineMatchNet {
  OnlineMatchNet({
    required this.link,
    required this.backend,
    required this.matchId,
    required Map<String, dynamic> roomSettings,
    required String roomHost,
    required bool ranked,
    required DiscStats Function(String disc) statsOf,
    double Function()? clock,
    Future<void> Function(Duration d)? wait,
    this.blueName = 'آبی',
    this.redName = 'قرمز',
  })  : _statsOf = statsOf,
        _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch / 1000.0),
        _wait = wait ?? ((Duration d) => Future<void>.delayed(d)),
        room0Host = roomHost {
    me = link.me;
    isHost = roomHost == me;
    final List<NetPlayer> players = link.players;
    final List<NetPlayer> t0 = teamOf(players, 0), t1 = teamOf(players, 1);
    final String d0 = t0.isNotEmpty ? t0.first.disc : 'club0';
    final String d1 = t1.isNotEmpty ? t1.first.disc : 'club0';
    _stats = <DiscStats?>[statsOf(d0), statsOf(d1)];
    teamIds = <String>[teamOfAvatar(d0).id, teamOfAvatar(d1).id];
    cfg = cfgFromRoomSettings(roomSettings, stats: _stats, teams: teamIds);
    eng = Engine(cfg);
    for (final NetPlayer p in players) {
      if (p.userId == me && p.role == 'player' && (p.team == 0 || p.team == 1)) myTeam = p.team!;
    }
    String nm(List<NetPlayer> t, String d) {
      String n = d;
      if (t.isNotEmpty && t.first.name.isNotEmpty) n = t.first.name;
      return n + (t.length > 1 ? ' +${t.length - 1}' : '');
    }

    names = <String>[nm(t0, blueName), nm(t1, redName)];
    this.ranked = ranked;
    flipped = myTeam == 1;
    final double now = _clock();
    t0s = now;
    lastRecv = now;
  }

  final MatchLink link;
  final MatchBackend backend;
  final String matchId;
  final String room0Host;
  final DiscStats Function(String disc) _statsOf;
  final double Function() _clock;
  final Future<void> Function(Duration d) _wait;
  final String blueName, redName;

  late final String me;
  late final bool isHost;
  late final MatchCfg cfg;
  late final Engine eng;
  late final List<DiscStats?> _stats;
  late final List<String> teamIds;
  late final List<String> names;
  late final bool ranked;
  late final bool flipped;

  /// -1 = spectator
  int myTeam = -1;
  NetDone done = NetDone.no;
  bool disposed = false;

  // ---- callbacks (UI)
  /// every engine event as it plays (host: on simulation, clients: when playback reaches it)
  void Function(EngineEvent e)? onEvent;
  void Function(NetOutcome o)? onFinish;

  /// 'quit' | 'hostLost' | 'aborted'
  void Function(String why)? onExit;
  void Function(String fa)? onToast;

  // ---- host state
  final List<int> turnCount = <int>[0, 0];
  int seq = 0;
  String hostCtrl = '';
  double lastSendMs = 0;
  int q = 0;
  List<List<int>> evs = <List<int>>[];
  late double t0s;
  double lastAim = 0;

  // ---- client state
  final List<_Buf> buf = <_Buf>[];
  final List<List<double>> offs = <List<double>>[];
  int applied = -1;
  late double lastRecv;
  double pendingShot = 0;
  _PendingShot? shot;
  Map<String, dynamic>? res;
  double endAt = 0;
  List<double> prev = <double>[];
  String clientCtrl = '';
  int clientSeq = 0;
  bool got = false;
  double claimAt = 0;
  bool claiming = false;
  double offAt = 0;

  /// my finger is down on this body
  Body? local;

  double get now => _clock();
  double get nowMs => _clock() * 1000.0;

  String get ctrl => isHost ? hostCtrl : clientCtrl;
  bool get myTurn => ctrl == me && eng.phase == Phase.aim && myTeam >= 0;

  /// waiting overlay: guest without snapshots / offline / host silent
  bool get waiting => !isHost && (!got || !link.connected || (done == NetDone.no && now - lastRecv > kHostSilence));

  void _send(Map<String, dynamic> m) {
    if (disposed) return;
    m['mid'] = matchId;
    link.send(m);
  }

  Body? _body(int id) {
    for (final Body b in eng.bodies) {
      if (b.id == id) return b;
    }
    return null;
  }

  // ======================================================================== events
  void _onEvent(EngineEvent ev) {
    if (ev.t == 'goal' && !ev.nogoal && !isHost) eng.fxGoal(ev.team);
    onEvent?.call(ev);
    if (ev.t == 'end' && done == NetDone.no) {
      done = NetDone.ended;
      if (isHost) {
        _hostReport(ev.score ?? <int>[eng.score[0], eng.score[1]]);
      } else {
        endAt = now;
      }
    }
  }

  // ======================================================================== host: result
  Future<void> _hostReport(List<int> score) async {
    sendSnap(true);
    final int dur = (now - t0s).round();
    int? d;
    bool ok = false;
    for (int i = 0; i < 3; i++) {
      final NetRes r = await backend.reportMatch(matchId, score[0], score[1], dur);
      if (disposed) return;
      if (r.ok) {
        d = r.data is Map ? _ni(r.map['rating_delta']) : 0;
        ok = true;
        break;
      }
      if (r.raw.toLowerCase().contains('not live')) break;
      await _wait(const Duration(milliseconds: 1500));
      if (disposed) return;
    }
    if (!ok) onToast?.call('ثبت نتیجه ناموفق بود');
    final int w = score[0] > score[1] ? 0 : (score[1] > score[0] ? 1 : -1);
    Map<String, dynamic> resMsg() => <String, dynamic>{'k': 'res', 'winner': w, 'rd': d ?? 0, 'score': <int>[score[0], score[1]], 'ok': ok};
    _send(resMsg());
    unawaited(_wait(const Duration(milliseconds: 400)).then((_) {
      if (!disposed) _send(resMsg());
    }));
    link.ping();
    await _wait(const Duration(milliseconds: 1100));
    if (done == NetDone.ended && !disposed) {
      done = NetDone.finished;
      onFinish?.call(outcome(score, d, ok));
    }
  }

  NetOutcome outcome(List<int> score, Object? d, bool reported) {
    final int w = score[0] > score[1] ? 0 : (score[1] > score[0] ? 1 : -1);
    int? rd;
    if (d != null) {
      if (!ranked) {
        rd = 0;
      } else if (myTeam == 1) {
        rd = -_ni(d);
      } else if (myTeam == 0) {
        rd = _ni(d);
      }
    }
    return NetOutcome(
      matchId: matchId,
      score: <int>[score[0], score[1]],
      winner: w,
      ratingDelta: rd,
      myTeam: myTeam >= 0 ? myTeam : null,
      teamIds: teamIds,
      names: names,
      reported: reported,
      ranked: ranked,
    );
  }

  // ======================================================================== host: snapshots
  void sendSnap([bool force = false]) {
    final double nms = nowMs;
    final int rec = math.max(1, link.onlineCount - 1);
    final int hz = rec <= 1 ? 30 : (rec <= 3 ? 25 : 20);
    final bool moving = eng.phase == Phase.move || eng.phase == Phase.goal;
    if (!force && nms - lastSendMs < (moving ? 1000.0 / hz : 500.0)) return;
    lastSendMs = nms;
    q++;
    final Snap s = Snap.capture(eng, q: q, ts: nms.round(), hz: hz, ctrl: hostCtrl.isNotEmpty ? hostCtrl : null, seq: seq, evs: evs);
    evs = <List<int>>[];
    _send(<String, dynamic>{'k': 's', 's': s.toJson()});
  }

  /// controller of team t for its current turn (rotation + skip offline humans); '' = bot
  String ctrlFor(int t) {
    final List<NetPlayer> team = teamOf(link.players, t);
    if (team.isEmpty) return '';
    final int n = team.length;
    final int st0 = ((turnCount[t] - 1) % n + n) % n;
    for (int i = 0; i < n; i++) {
      final String u = team[(st0 + i) % n].userId;
      if (u == me || link.isOnline(u)) return u;
    }
    return '';
  }

  // ======================================================================== client: snapshots
  void _applyScalars(Snap s) {
    eng.phase = s.ph;
    eng.turn = s.tu;
    eng.score = <int>[s.sc[0], s.sc[1]];
    eng.mleft = s.ml;
    eng.tleft = s.tl;
    eng.sudden = s.su != 0;
    clientCtrl = s.c ?? '';
    clientSeq = s.n;
    eng.aiTeams = <bool>[false, false];
    if (s.c == null) eng.aiTeams[s.tu] = true;
    if (s.ph != Phase.aim && eng.drag != null) eng.drag = null;
    for (final List<dynamic> e in s.ev) {
      _onEvent(decEv(e));
    }
  }

  /// Interpolates every body between snapshots a and b (k in 0..1, >1 = extrapolation).
  void placeBodies(Snap a, Snap? b, double k, double dt) {
    final int n = eng.bodies.length;
    final List<int> ap = a.p;
    if (ap.length < n * 3) return;
    if (prev.length != n * 2) prev = List<double>.filled(n * 2, 0);
    final List<int>? bp = (b != null && b.p.length >= n * 3) ? b.p : null;
    for (int i = 0; i < n; i++) {
      final Body bd = eng.bodies[i];
      double x = ap[i * 3] / 10.0;
      double y = ap[i * 3 + 1] / 10.0;
      double ang = ap[i * 3 + 2] / 100.0;
      if (bp != null) {
        x += (bp[i * 3] / 10.0 - x) * k;
        y += (bp[i * 3 + 1] / 10.0 - y) * k;
        double da = bp[i * 3 + 2] / 100.0 - ang;
        if (da > math.pi) {
          da -= kTau;
        } else if (da < -math.pi) {
          da += kTau;
        }
        ang += da * k;
      }
      final double px = prev[i * 2], py = prev[i * 2 + 1];
      final double ddt = math.max(dt, 0.001);
      bd.vx = got ? (x - px) / ddt : 0.0;
      bd.vy = got ? (y - py) / ddt : 0.0;
      if (bd.vx.abs() < 4) bd.vx = 0;
      if (bd.vy.abs() < 4) bd.vy = 0;
      bd.x = x;
      bd.px = x;
      bd.y = y;
      bd.py = y;
      bd.ang = ang;
      bd.vox = 0;
      bd.voy = 0;
      prev[i * 2] = x;
      prev[i * 2 + 1] = y;
    }
    final List<int> src = (b != null && k > 0.5) ? b.R : a.R;
    if (src.length == 9) {
      for (int j = 0; j < 9; j++) {
        eng.ball.R[j] = src[j] / 1000.0;
      }
    }
    got = true;
    eng.acc = 0;
  }

  // ======================================================================== network messages
  void onMsg(Map<String, dynamic> m, String? fromIn) {
    final String from = fromIn ?? '';
    final String k = '${m['k'] ?? ''}';
    if (disposed || (done == NetDone.finished && k != 'res')) return;
    if (m.containsKey('mid') && '${m['mid']}' != matchId) return; // stale message from another match in this room
    if (k == 's' && !isHost) {
      final Object? raw = m['s'];
      if (raw is! Map || raw['p'] is! List || !raw.containsKey('q') || !raw.containsKey('ts')) return;
      final List<String> hosts = <String>[room0Host, link.currentHost];
      if (from.isNotEmpty && !hosts.contains(from)) return; // only the host's snapshots count
      final Snap? s = Snap.fromJson(raw);
      if (s == null) return;
      final double nms = nowMs;
      lastRecv = now;
      final int qq = s.q;
      if (qq <= applied && got) return; // already played back
      for (final _Buf x in buf) {
        if (x.q == qq) return; // duplicate
      }
      final double ts = _nd(raw['ts']);
      offs.add(<double>[nms, nms - ts]);
      while (offs.isNotEmpty && nms - offs.first[0] > 4000) {
        offs.removeAt(0);
      }
      final _Buf nb = _Buf(qq, ts, s.hz, s);
      if (buf.isEmpty || qq > buf.last.q) {
        buf.add(nb);
      } else {
        buf.add(nb);
        buf.sort((_Buf a, _Buf b) => a.q.compareTo(b.q));
      }
      if (buf.length > 60) buf.removeRange(0, buf.length - 60);
      // shot acknowledged (seq moved on or the shot started)
      final _PendingShot? sh = shot;
      if (sh != null && (s.n != sh.n || s.ph != Phase.aim)) shot = null;
    } else if (k == 'shot' && isHost) {
      if (from != hostCtrl || eng.phase != Phase.aim || _ni(m['n'], -1) != seq) return;
      final Body? b = _body(_ni(m['b'], -999));
      if (b == null || b.team != eng.turn) return;
      final double dx = _nd(m['dx']), dy = _nd(m['dy']);
      final double l = math.sqrt(dx * dx + dy * dy);
      if (l > 18 && l < 5000) {
        _applyCtrlStats(from);
        eng.fire(b, dx, dy, l, human: true);
      }
    } else if (k == 'aim') {
      if (from != ctrl || from == me) return;
      final int bid = _ni(m['b'], -1);
      if (bid < 0) {
        final Drag? d = eng.drag;
        if (d != null && d.ai && !eng.isAiTurn()) eng.drag = null;
        return;
      }
      if (eng.phase != Phase.aim) return;
      final Body? b = _body(bid);
      if (b == null) return;
      eng.drag = Drag(b: b, sx: b.x, sy: b.y, cx: b.x - _nd(m['dx']), cy: b.y - _nd(m['dy']), ai: true);
    } else if (k == 'res' && !isHost) {
      final Object? sc = m['score'];
      res = <String, dynamic>{
        'winner': _ni(m['winner'], -1),
        'rd': m['rd'],
        'score': sc is List && sc.length == 2 ? <int>[_ni(sc[0]), _ni(sc[1])] : <int>[eng.score[0], eng.score[1]],
        'ok': m['ok'] == true,
      };
      if (done == NetDone.no) {
        // the end event was missed (late join / dropped snapshot): end now
        done = NetDone.ended;
        endAt = now;
      }
    } else if (k == 'abort' && !isHost && done != NetDone.finished && done != NetDone.aborted && (from.isEmpty || from == room0Host)) {
      done = NetDone.aborted;
      onToast?.call('میزبان بازی را لغو کرد');
      onExit?.call('aborted');
    }
  }

  /// the player in control flicks with their own equipped disc's stats (Godot c_stats)
  void _applyCtrlStats(String cu) {
    if (cu.isEmpty) return;
    for (final NetPlayer p in link.players) {
      if (p.userId == cu) {
        _stats[eng.turn] = _statsOf(p.disc);
        return;
      }
    }
  }

  // ======================================================================== main loop
  void tick(double dtIn) {
    if (disposed || done == NetDone.aborted) return;
    final double dt = math.min(0.1, dtIn);
    if (isHost) {
      _hostTick(dt);
    } else {
      _clientTick(dt, now);
    }
    if (eng.parts.length > 400) eng.parts.removeRange(400, eng.parts.length);
  }

  void _hostTick(double dt) {
    final String cu0 = hostCtrl;
    _applyCtrlStats(cu0);
    eng.update(dt);
    bool urgent = false;
    if (eng.events.isNotEmpty) {
      for (final EngineEvent ev in eng.events) {
        if (ev.t == 'turn') {
          turnCount[ev.team]++;
          seq++;
        }
        evs.add(encEv(ev));
        if (ev.t != 'hit' && ev.t != 'wall' && ev.t != 'post') urgent = true;
      }
      final List<EngineEvent> list = List<EngineEvent>.of(eng.events);
      eng.events.clear();
      // controller must be decided before the snapshot that announces the turn
      hostCtrl = eng.phase == Phase.over ? '' : ctrlFor(eng.turn);
      for (final EngineEvent ev in list) {
        _onEvent(ev);
      }
    }
    final String c = eng.phase == Phase.over ? '' : ctrlFor(eng.turn);
    if (c != hostCtrl) {
      hostCtrl = c;
      urgent = true;
      final Drag? d = eng.drag;
      if (c != me && d != null && !d.ai) {
        eng.drag = null;
        local = null;
      }
    }
    final bool ai = c.isEmpty && eng.phase != Phase.over;
    if (eng.aiTeams[eng.turn] != ai || eng.aiTeams[1 - eng.turn]) {
      eng.aiTeams = <bool>[false, false];
      eng.aiTeams[eng.turn] = ai;
      if (!ai) {
        eng.aiPlan = null;
        final Drag? d = eng.drag;
        if (d != null && d.ai) eng.drag = null;
      }
    }
    if (done != NetDone.finished) sendSnap(urgent);
  }

  void _clientTick(double dt, double nowS) {
    final double nms = nowS * 1000.0;
    double off = 0;
    if (offs.isNotEmpty) {
      off = double.infinity;
      for (final List<double> o in offs) {
        off = math.min(off, o[1]);
      }
    }
    double hz = buf.isNotEmpty ? buf.last.hz.toDouble() : 12.0;
    if (hz <= 0) hz = 12;
    final double rt = nms - off - 1700.0 / hz;
    for (final _Buf s in List<_Buf>.of(buf)) {
      if (s.q > applied && s.ts <= rt) {
        applied = s.q;
        _applyScalars(s.s);
      }
    }
    if (buf.isNotEmpty) {
      int i = 0;
      while (i + 1 < buf.length && buf[i + 1].ts <= rt) {
        i++;
      }
      final _Buf a = buf[i];
      final _Buf? b = i + 1 < buf.length ? buf[i + 1] : null;
      double k = 0;
      if (b != null) k = ((rt - a.ts) / math.max(1.0, b.ts - a.ts)).clamp(0.0, 1.0).toDouble();
      if (a.ts <= rt || !got) {
        if (applied < a.q && !got) {
          applied = a.q;
          _applyScalars(a.s);
        }
        final _Buf? pv = i > 0 ? buf[i - 1] : null;
        // buffer starved while things move → extrapolate from the last two snapshots for up to 120 ms
        if (b == null && pv != null && (a.s.ph == Phase.move || a.s.ph == Phase.goal) && rt > a.ts) {
          placeBodies(pv.s, a.s, 1.0 + math.min(120.0, rt - a.ts) / math.max(1.0, a.ts - pv.ts), dt);
        } else {
          placeBodies(a.s, b?.s, k, dt);
        }
      }
      if (i > 3) buf.removeRange(0, i - 3);
    }
    eng.tickFx(dt);
    // resend an unacknowledged shot (host dedupes by seq + phase)
    final _PendingShot? sh = shot;
    if (sh != null && done == NetDone.no && nowS - sh.at > 0.45) {
      if (sh.tries >= 3 || sh.n != clientSeq) {
        shot = null;
      } else {
        sh.tries++;
        sh.at = nowS;
        _send(Map<String, dynamic>.of(sh.msg));
      }
    }
    if (done == NetDone.no) {
      if (!link.connected) {
        if (offAt == 0) offAt = nowS;
        if (nowS - offAt > kSelfOfflineGiveUp) {
          done = NetDone.aborted;
          onToast?.call('ارتباط با میزبان قطع شد');
          onExit?.call('hostLost');
          return;
        }
      } else {
        if (offAt > 0) {
          // back online: silence while we were offline does not count against the host
          offAt = 0;
          lastRecv = math.max(lastRecv, nowS - 2.0);
        }
        final double silent = nowS - lastRecv;
        final bool hostOnline = link.isOnline(room0Host);
        final double limit = got ? kHostSilence : kFirstSnapWait;
        if (silent > limit || (!hostOnline && silent > 4.0 && got)) {
          if (silent > kHostGiveUp || (!got && myTeam < 0)) {
            done = NetDone.aborted;
            onToast?.call('ارتباط با میزبان قطع شد');
            onExit?.call('hostLost');
            return;
          }
          if (myTeam >= 0 && !claiming && nowS - claimAt > 5.0) _claimHostLost();
        }
      }
    }
    if (done == NetDone.ended) {
      final Map<String, dynamic>? r = res;
      if (r != null && nowS - endAt > 0.9) {
        done = NetDone.finished;
        onFinish?.call(outcome(List<int>.from(r['score'] as List<int>), r['rd'], r['ok'] == true));
      } else if (r == null && nowS - endAt > 10.0) {
        done = NetDone.finished;
        _finishFromDb();
      }
    }
  }

  Future<void> _claimHostLost() async {
    claiming = true;
    claimAt = now;
    final NetRes r = await backend.claimHostLost(matchId, <int>[eng.score[0], eng.score[1]]);
    claiming = false;
    if (disposed || done != NetDone.no) return;
    if (r.ok && r.data is Map) {
      final Map<String, dynamic> d = r.map;
      if ('${d['outcome'] ?? ''}' == 'forfeit') {
        done = NetDone.finished;
        final List<int> sc = <int>[_ni(d['score_a'], eng.score[0]), _ni(d['score_b'], eng.score[1])];
        onToast?.call('میزبان قطع شد؛ نتیجه ثبت شد');
        onFinish?.call(outcome(sc, d['rating_delta'], true));
        return;
      }
      done = NetDone.aborted;
      onToast?.call('ارتباط با میزبان قطع شد');
      onExit?.call('hostLost');
    } else if (r.raw.contains('not live')) {
      done = NetDone.ended;
      endAt = now - 9.0; // settled meanwhile (host reported): read the result from the DB
    }
    // "host still online" -> keep waiting, retry in 5 s
  }

  Future<void> _finishFromDb() async {
    final Map<String, dynamic>? r = await backend.fetchMatch(matchId);
    List<int> sc = <int>[eng.score[0], eng.score[1]];
    bool ok = false;
    if (r != null && '${r['status'] ?? ''}' == 'done') {
      sc = <int>[_ni(r['score_a'], sc[0]), _ni(r['score_b'], sc[1])];
      ok = true;
    }
    if (!disposed) onFinish?.call(outcome(sc, null, ok));
  }

  /// back from the background: never count our own pause as host silence
  void resumed() {
    lastRecv = now;
    if (!isHost) {
      offs.clear(); // clock offset re-estimated from fresh snapshots
      buf.clear();
      got = false; // snap to the next snapshot instead of interpolating across the gap
    }
  }

  // ======================================================================== input (world coordinates)
  bool canAct() {
    if (myTeam < 0 || done != NetDone.no) return false;
    if (isHost) return eng.phase == Phase.aim && hostCtrl == me && !eng.isAiTurn();
    return eng.phase == Phase.aim && clientCtrl == me && now - pendingShot > 1.5;
  }

  void _sendAim([bool force = false]) {
    final Drag? d = eng.drag;
    if (d == null || d.ai) return;
    final double t = now;
    if (!force && t - lastAim < 0.12) return;
    lastAim = t;
    _send(<String, dynamic>{'k': 'aim', 'b': d.b.id, 'dx': (d.sx - d.cx).round(), 'dy': (d.sy - d.cy).round()});
  }

  /// finger down; true when a disc was grabbed
  bool grant(double x, double y) {
    if (!canAct()) return false;
    if (isHost) {
      if (eng.pick(x, y)) {
        local = eng.drag?.b;
        return local != null;
      }
      return false;
    }
    Body? best;
    double bd = 1e9;
    for (final Body b in eng.bodies) {
      if (b.team == myTeam && b.team == eng.turn) {
        final double d = math.sqrt((x - b.x) * (x - b.x) + (y - b.y) * (y - b.y));
        if (d < b.r + 34 && d < bd) {
          best = b;
          bd = d;
        }
      }
    }
    if (best == null) return false;
    local = best;
    eng.drag = Drag(b: best, sx: best.x, sy: best.y, cx: x, cy: y, ai: false);
    return true;
  }

  void move(double x, double y) {
    final Drag? d = eng.drag;
    if (local == null || d == null || d.ai) return;
    eng.move(x, y);
    _sendAim();
  }

  void release() {
    final Body? l0 = local;
    local = null;
    if (l0 == null) return;
    final Drag? d = eng.drag;
    if (isHost) {
      _applyCtrlStats(hostCtrl);
      eng.release();
      _send(<String, dynamic>{'k': 'aim', 'b': -1});
      return;
    }
    eng.drag = null;
    _send(<String, dynamic>{'k': 'aim', 'b': -1});
    if (d == null || d.ai) return;
    final double dx = d.sx - d.cx, dy = d.sy - d.cy;
    final double l = math.sqrt(dx * dx + dy * dy);
    if (l > 18 && canAct()) {
      pendingShot = now;
      final Map<String, dynamic> msg = <String, dynamic>{
        'k': 'shot',
        'b': l0.id,
        'dx': (dx * 10).round() / 10.0,
        'dy': (dy * 10).round() / 10.0,
        'n': clientSeq,
      };
      shot = _PendingShot(Map<String, dynamic>.of(msg), clientSeq, now);
      _send(msg);
    }
  }

  void terminate() {
    local = null;
    final Drag? d = eng.drag;
    if (d != null && !d.ai) eng.drag = null;
    _send(<String, dynamic>{'k': 'aim', 'b': -1});
  }

  /// power 0..1 of my current drag (for the HUD)
  double get dragPower {
    final Drag? d = eng.drag;
    if (d == null) return 0;
    final double l = math.sqrt((d.sx - d.cx) * (d.sx - d.cx) + (d.sy - d.cy) * (d.sy - d.cy));
    return math.min(l, kOnlineLmax) / kOnlineLmax;
  }

  // ======================================================================== exit
  /// The user confirmed "quit": host ends the match for everyone (forfeit / abandon), others just leave.
  void quit() {
    if (isHost && done == NetDone.no) {
      done = NetDone.aborted;
      _send(<String, dynamic>{'k': 'abort'});
      backend.hostQuit(matchId, <int>[eng.score[0], eng.score[1]]);
    } else {
      done = NetDone.aborted;
    }
    onExit?.call('quit');
  }

  /// Screen torn down: a host leaving mid-match ends it for everyone.
  void dispose() {
    if (disposed) return;
    if (isHost && done == NetDone.no) {
      done = NetDone.aborted;
      _send(<String, dynamic>{'k': 'abort'});
      backend.hostQuit(matchId, <int>[eng.score[0], eng.score[1]]);
    }
    disposed = true;
  }
}
