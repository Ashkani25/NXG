/// One live online arcade match: server view, realtime updates, moves, clock, reconnect, forfeit.
///
///  * the authoritative state is `gm_view(match)`; realtime (game_state / game_private changes)
///    and a 4 s poll both just trigger a refetch, so a dropped socket never loses a move;
///  * views are ordered by `version` — an older view never replaces a newer one;
///  * the server clock offset comes from the view's `now`; when a deadline passes, any client
///    pokes `gm_tick` (the server also sweeps every 10 s), so idle players time out and three
///    idle turns in a row forfeit;
///  * [resign] forfeits; leaving the room makes the server drop the seat on its next tick.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'gm_backend.dart';
import 'gm_models.dart';

typedef GmErrorMapper = String Function(Object error);

class GmMatchController extends ChangeNotifier {
  GmMatchController({
    required this.matchId,
    required this.backend,
    required this.uid,
    this.isFa = true,
    GmErrorMapper? errorText,
    DateTime Function()? clock,
    bool autoStart = true,
    this.pollEvery = const Duration(seconds: 4),
  })  : _errorText = errorText,
        _clock = clock ?? DateTime.now {
    if (autoStart) start();
  }

  final String matchId;
  final GmBackend backend;
  final String uid;
  final bool isFa;
  final GmErrorMapper? _errorText;
  final DateTime Function() _clock;
  final Duration pollEvery;

  GmView? _view;
  GmView? get view => _view;

  /// Last error, already user-facing text. Cleared by the next successful call.
  String? error;

  /// A move / resign is in flight.
  bool busy = false;

  /// Realtime channel subscribed.
  bool connected = false;

  /// server time - local time
  Duration serverOffset = Duration.zero;

  GmWatch? _watch;
  Timer? _poll;
  Timer? _clockTimer;
  Timer? _debounce;
  bool _dead = false;
  bool _fetching = false;
  bool _refetchAgain = false;
  DateTime? _lastTick;
  final StreamController<GmView> _views = StreamController<GmView>.broadcast();

  /// Every accepted new view (newer version), for animations.
  Stream<GmView> get views => _views.stream;
  bool get disposed => _dead;

  void start() {
    if (_watch != null || _dead) return;
    _watch = backend.watch(matchId, uid, _soon, (bool c) {
      if (_dead) return;
      connected = c;
      notifyListeners();
    });
    _poll = Timer.periodic(pollEvery, (_) => refresh());
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) => _onClock());
    refresh();
  }

  void _soon() {
    if (_dead) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), refresh);
  }

  String _err(Object e) {
    final GmErrorMapper? m = _errorText;
    if (m != null) return m(e);
    return gmErrorText('$e', isFa);
  }

  /// Applies a view if it is newer than what we have (or a different match). Returns true if applied.
  @visibleForTesting
  bool accept(Map<String, dynamic> raw) {
    if (_dead || raw.isEmpty) return false;
    final GmView v = GmView(raw);
    final GmView? cur = _view;
    if (cur != null && cur.matchId == v.matchId && v.version < cur.version) return false;
    final DateTime? now = v.serverNow;
    if (now != null) serverOffset = now.difference(_clock().toUtc());
    final bool changed = cur == null || v.version != cur.version || v.status != cur.status;
    _view = v;
    if (changed && !_views.isClosed) _views.add(v);
    notifyListeners();
    return true;
  }

  /// Refetch the view now (reconnect / resume / realtime ping).
  Future<void> refresh() async {
    if (_dead) return;
    if (_fetching) {
      _refetchAgain = true;
      return;
    }
    _fetching = true;
    try {
      accept(await backend.view(matchId));
    } catch (e) {
      if (_view == null) {
        error = _err(e);
        notifyListeners();
      }
    } finally {
      _fetching = false;
    }
    if (_refetchAgain && !_dead) {
      _refetchAgain = false;
      await refresh();
    }
  }

  /// Time left on the current deadline (server-corrected).
  Duration get remaining => gmRemaining(_view?.deadline, _clock(), serverOffset);

  /// 0..1 fraction of [total] left (for timer rings).
  double remainingFraction(Duration total) {
    if (total.inMilliseconds <= 0) return 0;
    final double f = remaining.inMilliseconds / total.inMilliseconds;
    return f < 0 ? 0 : (f > 1 ? 1 : f);
  }

  void _onClock() {
    if (_dead) return;
    final GmView? v = _view;
    if (v == null || !v.live) return;
    notifyListeners(); // countdown redraw
    final DateTime? dl = v.deadline;
    if (dl == null) return;
    final DateTime serverNow = _clock().toUtc().add(serverOffset);
    if (serverNow.isBefore(dl.add(const Duration(milliseconds: 1200)))) return;
    final DateTime local = _clock();
    if (_lastTick != null && local.difference(_lastTick!) < const Duration(seconds: 3)) return;
    _lastTick = local;
    tick();
  }

  /// Ask the server to act on an overdue deadline.
  Future<void> tick() async {
    if (_dead) return;
    try {
      accept(await backend.tick(matchId));
    } catch (_) {/* the cron sweep will do it */}
  }

  /// Sends a move. Returns true when the server accepted it.
  Future<bool> move(GmMove m) async {
    final GmView? v = _view;
    if (_dead || v == null || busy) return false;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final Map<String, dynamic> r =
          await backend.move(matchId, m.toJson(), version: GmMove.versioned(v.game) ? v.version : null);
      busy = false;
      accept(r);
      return true;
    } catch (e) {
      busy = false;
      error = _err(e);
      notifyListeners();
      refresh();
      return false;
    }
  }

  /// Host-authoritative games: report the shot I just simulated.
  Future<bool> shot(Map<String, dynamic> state, int nextTurn, {Map<String, dynamic>? finish}) async {
    final GmView? v = _view;
    if (_dead || v == null || busy) return false;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final Map<String, dynamic> r = await backend.shot(matchId, v.version, state, nextTurn, finish: finish);
      busy = false;
      accept(r);
      return true;
    } catch (e) {
      busy = false;
      error = _err(e);
      notifyListeners();
      refresh();
      return false;
    }
  }

  /// Forfeit the match.
  Future<bool> resign() async {
    if (_dead) return false;
    try {
      accept(await backend.resign(matchId));
      return true;
    } catch (e) {
      error = _err(e);
      notifyListeners();
      return false;
    }
  }

  void clearError() {
    if (error == null) return;
    error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_dead) return;
    _dead = true;
    _poll?.cancel();
    _clockTimer?.cancel();
    _debounce?.cancel();
    final GmWatch? w = _watch;
    _watch = null;
    if (w != null) w.close().catchError((Object _) {});
    _views.close();
    super.dispose();
  }
}
