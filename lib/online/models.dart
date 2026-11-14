/// Row types shared with the Expo app (src/net/supabase.ts). Thin, null-safe views over the JSON
/// rows PostgREST returns; `raw` keeps every column so new server columns never get lost.
library;

int _i(Object? v, [int d = 0]) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? d;
int? _in(Object? v) => v == null ? null : (v is num ? v.toInt() : int.tryParse('$v'));
String _s(Object? v, [String d = '']) => v == null ? d : '$v';
Map<String, dynamic> _m(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

/// Game ids that can run in a room. `football` is Disc Football (the only one the live backend
/// has rules for today); games-online adds the rest. Stored in `rooms.settings.game`
/// (or a top-level `rooms.game` column if the backend adds one later).
const String kDefaultGame = 'football';

class Room {
  Room(this.raw);
  factory Room.fromJson(Map<String, dynamic> j) => Room(Map<String, dynamic>.from(j));
  final Map<String, dynamic> raw;

  String get id => _s(raw['id']);
  String get code => _s(raw['code']);
  String get name => _s(raw['name'], 'اتاق');
  String get host => _s(raw['host']);
  String get mode => _s(raw['mode'], '1v1');
  String get status => _s(raw['status'], 'waiting'); // waiting | playing | finished
  bool get isPrivate => raw['is_private'] == true;
  bool get ranked => raw['ranked'] == true;
  bool get voice => raw['voice'] != false;
  Map<String, dynamic> get settings => _m(raw['settings']);
  String? get tournamentMatchId => raw['tournament_match_id'] as String?;
  String? get currentMatch => raw['current_match'] as String?;
  String get kind => _s(raw['kind'], 'casual'); // casual | quick | arena | tournament | duel | social
  String? get tier => raw['tier'] as String?;

  /// Which game this room plays (game-agnostic lobby).
  String get game => _s(raw['game'] ?? settings['game'], kDefaultGame);
  int get teamSz => teamSizeOf(mode);
  bool get playing => status == 'playing';
}

int teamSizeOf(String mode) => mode == '1v1' ? 1 : mode == '2v2' ? 2 : 3;

class MiniProfile {
  MiniProfile(this.raw);
  final Map<String, dynamic> raw;
  String get username => _s(raw['username'], '…');
  String get avatar => _s(raw['avatar']);
  String? get avatarUrl => raw['avatar_url'] as String?;
  int get level => _i(raw['level'], 1);
  int get rating => _i(raw['rating'], 1000);
  String get league => _s(raw['league']);
  String get equippedDisc => _s(raw['equipped_disc']);
}

class RoomPlayer {
  RoomPlayer(this.raw);
  factory RoomPlayer.fromJson(Map<String, dynamic> j) => RoomPlayer(Map<String, dynamic>.from(j));
  final Map<String, dynamic> raw;
  String get roomId => _s(raw['room_id']);
  String get userId => _s(raw['user_id']);
  String get role => _s(raw['role'], 'player'); // player | spectator
  bool get isPlayer => role == 'player';
  int? get team => _in(raw['team']);
  int? get slot => _in(raw['slot']);
  bool get ready => raw['ready'] == true;
  String? get discId => raw['disc_id'] as String?;
  MiniProfile? get profile => raw['profiles'] is Map ? MiniProfile(_m(raw['profiles'])) : null;
  String get name => profile?.username ?? '…';
  /// disc shown for this player (same fallback chain as OnlineMatch.discOf)
  String get disc => discId ?? (profile?.equippedDisc.isNotEmpty == true ? profile!.equippedDisc : (profile?.avatar.isNotEmpty == true ? profile!.avatar : 'club0'));
}

class OnlineProfile {
  OnlineProfile(this.raw);
  final Map<String, dynamic> raw;
  String get id => _s(raw['id']);
  String get username => _s(raw['username'], 'Pilot');
  String get avatar => _s(raw['avatar']);
  String? get avatarUrl => raw['avatar_url'] as String?;
  String? get bio => raw['bio'] as String?;
  int get xp => _i(raw['xp']);
  int get level => _i(raw['level'], 1);
  int get coins => _i(raw['coins']);
  int get gems => _i(raw['gems']);
  int get rating => _i(raw['rating'], 1000);
  String get league => _s(raw['league']);
  int get wins => _i(raw['wins']);
  int get losses => _i(raw['losses']);
  int get draws => _i(raw['draws']);
  int get goals => _i(raw['goals']);
  int get trophies => _i(raw['trophies']);
  bool get isGuest => raw['is_guest'] == true;
  String? get clubId => raw['club_id'] as String?;
  String get equippedDisc => _s(raw['equipped_disc'], 'club0');
  int get arenaPoints => _i(raw['arena_points']);
  int get winStreak => _i(raw['win_streak']);
  int get bestStreak => _i(raw['best_streak']);
  String get role => _s(raw['role'], 'player');
  int get played => wins + losses + draws;
}

/// What an online match screen hands back when it ends (OnlineOutcome in OnlineMatch.tsx).
class OnlineOutcome {
  const OnlineOutcome({
    required this.matchId,
    required this.score,
    required this.winner,
    required this.ratingDelta,
    required this.myTeam,
    required this.names,
    required this.reported,
    required this.ranked,
    this.teams = const ['', ''],
    this.game = kDefaultGame,
  });
  final String matchId;
  final (int, int) score;
  /// -1 draw, 0 team A (blue), 1 team B (red)
  final int winner;
  final int? ratingDelta;
  /// null = spectator
  final int? myTeam;
  /// team art keys (football: disc team ids)
  final List<String> teams;
  final List<String> names;
  final bool reported;
  final bool ranked;
  final String game;

  bool get won => myTeam != null && winner == myTeam;
  bool get draw => winner == -1;
}
