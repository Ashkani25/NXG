/// Online arcade games: wire models shared by every game (pure Dart, no Flutter).
///
/// The server (supabase/migrations/20261112100000_games_online_core.sql + per-game modules) owns the
/// rules: it rolls every die, deals every card, validates every move and runs the clocks. A client
/// only reads `gm_view(match)` and sends intents with `gm_move(match, move, version)`.
library;

/// Static facts about one online-capable arcade game.
class GmGameSpec {
  const GmGameSpec({
    required this.id,
    required this.nameFa,
    required this.nameEn,
    required this.minSeats,
    required this.maxSeats,
    required this.defaultSeats,
    required this.hostAuthority,
    required this.playable,
  });

  /// Registry / server game id (rooms.game).
  final String id;
  final String nameFa;
  final String nameEn;
  final int minSeats;
  final int maxSeats;
  final int defaultSeats;

  /// Physics games: the shooter simulates and reports (gm_shot); the server checks turn order only.
  final bool hostAuthority;

  /// True when this client has a finished online board for the game.
  final bool playable;

  List<int> get seatChoices => <int>[for (int i = minSeats; i <= maxSeats; i++) i];
}

/// Same bounds as `_gm_bounds` on the server.
const List<GmGameSpec> kGmGames = <GmGameSpec>[
  GmGameSpec(id: 'backgammon', nameFa: 'تخته‌نرد', nameEn: 'Backgammon', minSeats: 2, maxSeats: 2, defaultSeats: 2, hostAuthority: false, playable: true),
  GmGameSpec(id: 'ludo', nameFa: 'منچ', nameEn: 'Ludo', minSeats: 2, maxSeats: 4, defaultSeats: 4, hostAuthority: false, playable: true),
  GmGameSpec(id: 'snakes_ladders', nameFa: 'مار و پله', nameEn: 'Snakes & Ladders', minSeats: 2, maxSeats: 4, defaultSeats: 2, hostAuthority: false, playable: true),
  GmGameSpec(id: 'uno', nameFa: 'کارت‌های NX', nameEn: 'NX Cards', minSeats: 2, maxSeats: 6, defaultSeats: 4, hostAuthority: false, playable: true),
  GmGameSpec(id: 'quiz', nameFa: 'کوییز', nameEn: 'Quiz', minSeats: 2, maxSeats: 4, defaultSeats: 2, hostAuthority: false, playable: true),
  GmGameSpec(id: 'mafia', nameFa: 'مافیا', nameEn: 'Mafia', minSeats: 6, maxSeats: 12, defaultSeats: 8, hostAuthority: false, playable: true),
  GmGameSpec(id: 'carrom', nameFa: 'کرم', nameEn: 'Carrom', minSeats: 2, maxSeats: 2, defaultSeats: 2, hostAuthority: true, playable: true),
  GmGameSpec(id: 'billiards', nameFa: 'بیلیارد', nameEn: 'Billiards', minSeats: 2, maxSeats: 2, defaultSeats: 2, hostAuthority: true, playable: true),
];

GmGameSpec? gmSpec(String id) {
  for (final GmGameSpec s in kGmGames) {
    if (s.id == id) return s;
  }
  return null;
}

/// Game ids whose online mode really works end-to-end in this build.
List<String> get gmPlayableGames => <String>[for (final GmGameSpec s in kGmGames) if (s.playable) s.id];

// ------------------------------------------------------------------ json helpers
int gmInt(Object? v, [int d = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? d;
  return d;
}

int? gmIntOrNull(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

bool gmBool(Object? v) => v == true || v == 'true';

List<int> gmInts(Object? v) {
  if (v is! List) return <int>[];
  return <int>[for (final Object? x in v) gmInt(x)];
}

List<int?> gmIntsOrNull(Object? v) {
  if (v is! List) return <int?>[];
  return <int?>[for (final Object? x in v) gmIntOrNull(x)];
}

List<bool> gmBools(Object? v) {
  if (v is! List) return <bool>[];
  return <bool>[for (final Object? x in v) gmBool(x)];
}

Map<String, dynamic> gmMap(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<Map<String, dynamic>> gmMaps(Object? v) {
  if (v is! List) return <Map<String, dynamic>>[];
  return <Map<String, dynamic>>[for (final Object? x in v) if (x is Map) Map<String, dynamic>.from(x)];
}

DateTime? gmTime(Object? v) {
  if (v is! String || v.isEmpty) return null;
  return DateTime.tryParse(v)?.toUtc();
}

enum GmStatus { live, finished, abandoned }

GmStatus gmStatusOf(String s) {
  switch (s) {
    case 'finished':
      return GmStatus.finished;
    case 'abandoned':
      return GmStatus.abandoned;
    default:
      return GmStatus.live;
  }
}

/// What `gm_view(match)` returns: public state + my private data.
class GmView {
  GmView(this.raw)
      : matchId = '${raw['match_id'] ?? ''}',
        roomId = raw['room_id'] == null ? null : '${raw['room_id']}',
        game = '${raw['game'] ?? ''}',
        seats = <String>[for (final Object? s in (raw['seats'] is List ? raw['seats'] as List<dynamic> : <dynamic>[])) '$s'],
        names = <String>[for (final Object? s in (raw['names'] is List ? raw['names'] as List<dynamic> : <dynamic>[])) '${s ?? '…'}'],
        status = gmStatusOf('${raw['status'] ?? 'live'}'),
        phase = '${raw['phase'] ?? ''}',
        turn = gmInt(raw['turn']),
        version = gmInt(raw['version']),
        state = gmMap(raw['state']),
        deadline = gmTime(raw['deadline']),
        serverNow = gmTime(raw['now']),
        result = raw['result'] is Map ? Map<String, dynamic>.from(raw['result'] as Map) : null,
        hostAuthority = raw['authority'] == 'host',
        ranked = raw['ranked'] != false,
        mySeat = gmIntOrNull(raw['my_seat']),
        private = gmMap(raw['private']);

  factory GmView.fromJson(Object? j) => GmView(gmMap(j));

  final Map<String, dynamic> raw;
  final String matchId;
  final String? roomId;
  final String game;

  /// seat index -> user id
  final List<String> seats;
  final List<String> names;
  final GmStatus status;
  final String phase;
  final int turn;
  final int version;

  /// Public game state (game specific, see each game's online adapter).
  final Map<String, dynamic> state;
  final DateTime? deadline;

  /// Server clock at the moment of this view (for clock-offset correction).
  final DateTime? serverNow;
  final Map<String, dynamic>? result;
  final bool hostAuthority;
  final bool ranked;

  /// My seat, or null when I am a spectator.
  final int? mySeat;

  /// My private data (hand, role, …).
  final Map<String, dynamic> private;

  int get seatCount => seats.length;
  bool get live => status == GmStatus.live;
  bool get finished => status == GmStatus.finished;
  bool get abandoned => status == GmStatus.abandoned;
  bool get isPlayer => mySeat != null;
  bool get myTurn => live && mySeat != null && mySeat == turn && !isOut(mySeat!);

  String nameOf(int seat) => seat >= 0 && seat < names.length ? names[seat] : '…';

  bool isOut(int seat) {
    final List<bool> o = gmBools(state['out']);
    return seat >= 0 && seat < o.length && o[seat];
  }

  List<int> get scores => gmInts(state['scores']);
  int strikesOf(int seat) {
    final List<int> s = gmInts(state['strikes']);
    return seat >= 0 && seat < s.length ? s[seat] : 0;
  }

  List<int> get winners => gmInts(result?['winners']);
  String get reason => '${result?['reason'] ?? ''}';
  List<int> get ratingDelta => gmInts(result?['rating_delta']);
  List<int> get resultScores => gmInts(result?['scores']);

  /// Outcome for me: 1 win, 0 draw, -1 loss, null when not finished / spectator.
  int? get myOutcome {
    if (!finished || mySeat == null) return null;
    final List<int> w = winners;
    if (w.isEmpty || w.length == seatCount) return 0;
    return w.contains(mySeat) ? 1 : -1;
  }

  int? get myRatingDelta {
    final int? s = mySeat;
    final List<int> d = ratingDelta;
    if (s == null || s >= d.length) return null;
    return d[s];
  }
}

/// A move the client wants to make (`gm_move` p_move).
class GmMove {
  const GmMove(this.action, [this.args = const <String, dynamic>{}]);
  final String action;
  final Map<String, dynamic> args;
  Map<String, dynamic> toJson() => <String, dynamic>{'a': action, ...args};

  /// Turn-based games send the version they saw (stale moves are rejected); simultaneous games don't.
  static bool versioned(String game) => game != 'quiz' && game != 'mafia';
}

/// Remaining time on the clock, corrected by the client/server offset.
Duration gmRemaining(DateTime? deadline, DateTime localNow, Duration serverOffset) {
  if (deadline == null) return Duration.zero;
  final Duration d = deadline.difference(localNow.toUtc().add(serverOffset));
  return d.isNegative ? Duration.zero : d;
}

/// Persian / English text for the server errors games raise.
String gmErrorText(String raw, bool fa) {
  final String m = raw.toLowerCase();
  String pick(String a, String b) => fa ? a : b;
  if (m.contains('not your turn')) return pick('نوبت تو نیست', 'Not your turn');
  if (m.contains('stale version')) return pick('وضعیت عوض شد؛ دوباره امتحان کن', 'The game moved on — try again');
  if (m.contains('illegal') || m.contains('bad target') || m.contains('bad move')) return pick('این حرکت مجاز نیست', 'That move is not allowed');
  if (m.contains('must play')) return pick('باید همه‌ی تاس‌های قابل‌بازی را بازی کنی', 'You must play every playable die');
  if (m.contains('roll first')) return pick('اول تاس بریز', 'Roll first');
  if (m.contains('draw first')) return pick('اول کارت بکش', 'Draw first');
  if (m.contains('already drew')) return pick('این نوبت کارت کشیدی', 'You already drew this turn');
  if (m.contains('play the drawn card')) return pick('فقط کارت کشیده‌شده را می‌توانی بازی کنی', 'Only the drawn card can be played');
  if (m.contains('choose a colour')) return pick('یک رنگ انتخاب کن', 'Choose a colour');
  if (m.contains('already answered')) return pick('قبلاً جواب دادی', 'Already answered');
  if (m.contains('match over')) return pick('بازی تمام شده', 'The match is over');
  if (m.contains('you are out')) return pick('تو از بازی خارج شده‌ای', 'You are out of this match');
  if (m.contains('not a player')) return pick('تو تماشاگری', 'You are spectating');
  if (m.contains('not now')) return pick('الان وقتش نیست', 'Not right now');
  if (m.contains('nothing to catch')) return pick('کسی برای گرفتن نیست', 'Nobody to catch');
  if (m.contains('need') && m.contains('players')) return pick('بازیکن کافی نیست', 'Not enough players');
  if (m.contains('take a seat')) return pick('اول یک صندلی بگیر', 'Take a seat first');
  if (m.contains('not all ready')) return pick('همه آماده نیستند', 'Not everyone is ready');
  if (m.contains('host only')) return pick('فقط میزبان', 'Host only');
  if (m.contains('seat taken')) return pick('این صندلی گرفته شده', 'Seat taken');
  if (m.contains('room not found')) return pick('اتاق پیدا نشد', 'Room not found');
  if (m.contains('not signed in') || m.contains('jwt')) return pick('اول وارد حساب شو', 'Sign in first');
  if (m.contains('network') || m.contains('socket') || m.contains('timeout') || m.contains('failed host')) {
    return pick('اتصال اینترنت برقرار نیست', 'No internet connection');
  }
  return pick('خطا: ', 'Error: ') + (raw.length > 80 ? raw.substring(0, 80) : raw);
}
