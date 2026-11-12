import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/local_store.dart';
import 'achievements.dart';

/// A recorded activity (shown in Personal Orbit timeline).
class ActivityEntry {
  ActivityEntry({required this.at, required this.kind, required this.textFa, required this.textEn, this.xp = 0});
  final DateTime at;
  final String kind;
  final String textFa;
  final String textEn;
  final int xp;

  Map<String, dynamic> toJson() =>
      {'at': at.millisecondsSinceEpoch, 'kind': kind, 'fa': textFa, 'en': textEn, 'xp': xp};
  static ActivityEntry fromJson(Map<String, dynamic> j) => ActivityEntry(
        at: DateTime.fromMillisecondsSinceEpoch((j['at'] as num).toInt()),
        kind: j['kind'] as String? ?? 'misc',
        textFa: j['fa'] as String? ?? '',
        textEn: j['en'] as String? ?? '',
        xp: (j['xp'] as num?)?.toInt() ?? 0,
      );
}

/// Per-game statistics.
class GameStats {
  GameStats({this.played = 0, this.won = 0, this.lost = 0, this.draw = 0, this.best = 0});
  int played;
  int won;
  int lost;
  int draw;
  int best;
  Map<String, dynamic> toJson() => {'p': played, 'w': won, 'l': lost, 'd': draw, 'b': best};
  static GameStats fromJson(Map<String, dynamic> j) => GameStats(
        played: (j['p'] as num?)?.toInt() ?? 0,
        won: (j['w'] as num?)?.toInt() ?? 0,
        lost: (j['l'] as num?)?.toInt() ?? 0,
        draw: (j['d'] as num?)?.toInt() ?? 0,
        best: (j['b'] as num?)?.toInt() ?? 0,
      );
}

/// Result of an award call, so UI can celebrate level-ups / unlocks.
class AwardOutcome {
  AwardOutcome({required this.xp, required this.coins, required this.levelUp, required this.newLevel, required this.unlocked});
  final int xp;
  final int coins;
  final bool levelUp;
  final int newLevel;
  final List<AchievementDef> unlocked;
}

/// Single digital identity (Vision §2): same across every world.
/// Offline: authoritative locally. Online later: the BackendGateway mirrors this
/// and the server becomes the source of truth for XP (P21).
class ProfileService extends ChangeNotifier {
  ProfileService(this._store) {
    _load();
  }

  final LocalStore _store;
  static const _key = 'profile.v1';
  static const dailyXpCap = 3000;

  late String explorerId;
  String username = '';
  String bio = '';
  String avatarCore = 'hero_front';
  int xp = 0;
  int coins = 0;
  int crystals = 0;
  final Map<String, String> equipped = {}; // slot -> itemId
  final Set<String> inventory = {};
  final Set<String> achievements = {};
  final Map<String, GameStats> stats = {};
  final List<ActivityEntry> activity = [];
  final Map<String, int> counters = {}; // generic counters for achievements/challenges
  final Map<String, Map<String, dynamic>> decorLayout = {}; // decorId -> {x,y,s}
  String orbitTheme = 'aurora';
  DateTime createdAt = DateTime.now();
  String _xpDay = '';
  int _xpToday = 0;
  String claimedDaily = '';
  int streak = 0;

  bool get hasIdentity => username.isNotEmpty;

  void _load() {
    final j = _store.getJson(_key);
    if (j == null) {
      explorerId = _newExplorerId();
      coins = 500; // starter credits, earned/spent only through real actions afterwards
      inventory.addAll(const ['puck_nx_green', 'puck_tech_nx', 'theme_aurora', 'striker_soccer', 'cue_classic']);
      equipped['puck'] = 'puck_nx_green';
      equipped['striker'] = 'striker_soccer';
      equipped['cue'] = 'cue_classic';
      _save();
      return;
    }
    explorerId = j['id'] as String? ?? _newExplorerId();
    username = j['username'] as String? ?? '';
    bio = j['bio'] as String? ?? '';
    avatarCore = j['avatar'] as String? ?? 'hero_front';
    xp = (j['xp'] as num?)?.toInt() ?? 0;
    coins = (j['coins'] as num?)?.toInt() ?? 0;
    crystals = (j['crystals'] as num?)?.toInt() ?? 0;
    orbitTheme = j['orbitTheme'] as String? ?? 'aurora';
    claimedDaily = j['claimedDaily'] as String? ?? '';
    streak = (j['streak'] as num?)?.toInt() ?? 0;
    _xpDay = j['xpDay'] as String? ?? '';
    _xpToday = (j['xpToday'] as num?)?.toInt() ?? 0;
    createdAt = DateTime.fromMillisecondsSinceEpoch((j['created'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch);
    (j['equipped'] as Map?)?.forEach((k, v) => equipped['$k'] = '$v');
    inventory.addAll(((j['inv'] as List?) ?? const []).map((e) => '$e'));
    achievements.addAll(((j['ach'] as List?) ?? const []).map((e) => '$e'));
    (j['stats'] as Map?)?.forEach((k, v) => stats['$k'] = GameStats.fromJson(Map<String, dynamic>.from(v as Map)));
    (j['counters'] as Map?)?.forEach((k, v) => counters['$k'] = (v as num).toInt());
    (j['decor'] as Map?)?.forEach((k, v) => decorLayout['$k'] = Map<String, dynamic>.from(v as Map));
    activity.addAll(((j['act'] as List?) ?? const [])
        .map((e) => ActivityEntry.fromJson(Map<String, dynamic>.from(e as Map))));
  }

  Future<void> _save() => _store.setJson(_key, {
        'id': explorerId,
        'username': username,
        'bio': bio,
        'avatar': avatarCore,
        'xp': xp,
        'coins': coins,
        'crystals': crystals,
        'orbitTheme': orbitTheme,
        'claimedDaily': claimedDaily,
        'streak': streak,
        'xpDay': _xpDay,
        'xpToday': _xpToday,
        'created': createdAt.millisecondsSinceEpoch,
        'equipped': equipped,
        'inv': inventory.toList(),
        'ach': achievements.toList(),
        'stats': stats.map((k, v) => MapEntry(k, v.toJson())),
        'counters': counters,
        'decor': decorLayout,
        'act': activity.take(200).map((e) => e.toJson()).toList(),
      });

  static String _newExplorerId() {
    final r = Random.secure();
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    String block() => List.generate(4, (_) => chars[r.nextInt(chars.length)]).join();
    return 'NX-${block()}-${block()}';
  }

  // ---------- Levels ----------
  /// XP needed to go from level n to n+1.
  static int xpForLevel(int level) => 100 + (level - 1) * 75;

  int get level {
    var l = 1;
    var remaining = xp;
    while (remaining >= xpForLevel(l)) {
      remaining -= xpForLevel(l);
      l++;
    }
    return l;
  }

  /// Progress inside current level 0..1
  double get levelProgress {
    var l = 1;
    var remaining = xp;
    while (remaining >= xpForLevel(l)) {
      remaining -= xpForLevel(l);
      l++;
    }
    return remaining / xpForLevel(l);
  }

  int get xpIntoLevel {
    var l = 1;
    var remaining = xp;
    while (remaining >= xpForLevel(l)) {
      remaining -= xpForLevel(l);
      l++;
    }
    return remaining;
  }

  String get rankTitleEn {
    final l = level;
    if (l >= 40) return 'Cosmic Legend';
    if (l >= 25) return 'Star Commander';
    if (l >= 15) return 'Nebula Captain';
    if (l >= 8) return 'Orbit Pilot';
    if (l >= 3) return 'Navigator';
    return 'Cadet';
  }

  String get rankTitleFa {
    final l = level;
    if (l >= 40) return 'افسانه‌ی کیهانی';
    if (l >= 25) return 'فرمانده‌ی ستاره';
    if (l >= 15) return 'کاپیتان سحابی';
    if (l >= 8) return 'خلبان مدار';
    if (l >= 3) return 'ناوبر';
    return 'کادت';
  }

  // ---------- Identity ----------
  Future<void> createIdentity({required String name, String avatar = 'hero_front'}) async {
    username = name.trim();
    avatarCore = avatar;
    _log('identity', 'هویت دیجیتال ساخته شد: $username', 'Digital identity created: $username');
    await _save();
    notifyListeners();
  }

  Future<void> updateProfile({String? name, String? newBio}) async {
    if (name != null && name.trim().isNotEmpty) username = name.trim();
    if (newBio != null) bio = newBio;
    await _save();
    notifyListeners();
  }

  // ---------- Progression ----------
  String _today() {
    final n = DateTime.now();
    return '${n.year}-${n.month}-${n.day}';
  }

  /// Award XP/coins for a real event. Applies daily cap (anti-farm).
  AwardOutcome award(String event, {int xp = 0, int coins = 0, String? fa, String? en}) {
    final today = _today();
    if (_xpDay != today) {
      _xpDay = today;
      _xpToday = 0;
    }
    final allowed = max(0, min(xp, dailyXpCap - _xpToday));
    final before = level;
    this.xp += allowed;
    _xpToday += allowed;
    this.coins += coins;
    bump('event.$event');
    if (fa != null || en != null) _log(event, fa ?? en ?? event, en ?? fa ?? event, xp: allowed);
    final unlocked = _checkAchievements();
    _save();
    notifyListeners();
    return AwardOutcome(xp: allowed, coins: coins, levelUp: level > before, newLevel: level, unlocked: unlocked);
  }

  void bump(String counter, [int by = 1]) {
    counters[counter] = (counters[counter] ?? 0) + by;
  }

  int counter(String key) => counters[key] ?? 0;

  /// Record a finished match. Returns the award outcome.
  AwardOutcome recordGame({
    required String gameId,
    required String gameNameFa,
    required String gameNameEn,
    required String outcome, // win | loss | draw
    int score = 0,
    bool vsBot = true,
  }) {
    final s = stats.putIfAbsent(gameId, () => GameStats());
    s.played++;
    if (outcome == 'win') s.won++;
    if (outcome == 'loss') s.lost++;
    if (outcome == 'draw') s.draw++;
    if (score > s.best) s.best = score;
    bump('games.played');
    if (outcome == 'win') bump('games.won');
    bump('game.$gameId.played');
    final xpGain = switch (outcome) { 'win' => 60, 'draw' => 30, _ => 15 };
    final coinGain = switch (outcome) { 'win' => 40, 'draw' => 15, _ => 5 };
    final res = outcome == 'win' ? 'برد' : outcome == 'draw' ? 'مساوی' : 'باخت';
    final resEn = outcome == 'win' ? 'Won' : outcome == 'draw' ? 'Draw' : 'Lost';
    return award('game.$gameId.$outcome',
        xp: xpGain, coins: coinGain, fa: '$res در $gameNameFa', en: '$resEn at $gameNameEn');
  }

  int get totalGamesPlayed => stats.values.fold(0, (a, s) => a + s.played);
  int get totalWins => stats.values.fold(0, (a, s) => a + s.won);

  // ---------- Daily reward ----------
  bool get canClaimDaily => claimedDaily != _today();

  AwardOutcome? claimDaily() {
    if (!canClaimDaily) return null;
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final y = '${yesterday.year}-${yesterday.month}-${yesterday.day}';
    streak = claimedDaily == y ? streak + 1 : 1;
    claimedDaily = _today();
    final bonus = 50 + min(streak, 7) * 10;
    return award('daily', xp: 25, coins: bonus, fa: 'جایزه‌ی روزانه (روز $streak)', en: 'Daily reward (day $streak)');
  }

  // ---------- Economy (P26: no gambling, no random paid rewards) ----------
  bool owns(String itemId) => inventory.contains(itemId);

  bool purchase(String itemId, int price, {String? nameFa, String? nameEn}) {
    if (owns(itemId) || coins < price) return false;
    coins -= price;
    inventory.add(itemId);
    bump('shop.bought');
    _log('shop', 'خرید: ${nameFa ?? itemId}', 'Purchased: ${nameEn ?? itemId}');
    _checkAchievements();
    _save();
    notifyListeners();
    return true;
  }

  void grantItem(String itemId) {
    inventory.add(itemId);
    _save();
    notifyListeners();
  }

  void equip(String slot, String itemId) {
    if (!owns(itemId)) return;
    equipped[slot] = itemId;
    _save();
    notifyListeners();
  }

  void unequip(String slot) {
    equipped.remove(slot);
    _save();
    notifyListeners();
  }

  void setOrbitTheme(String theme) {
    orbitTheme = theme;
    _save();
    notifyListeners();
  }

  void placeDecor(String decorId, double x, double y, double scale) {
    decorLayout[decorId] = {'x': x, 'y': y, 's': scale};
    _save();
    notifyListeners();
  }

  void removeDecor(String decorId) {
    decorLayout.remove(decorId);
    _save();
    notifyListeners();
  }

  void logActivity(String kind, String fa, String en) {
    _log(kind, fa, en);
    _save();
    notifyListeners();
  }

  void _log(String kind, String fa, String en, {int xp = 0}) {
    activity.insert(0, ActivityEntry(at: DateTime.now(), kind: kind, textFa: fa, textEn: en, xp: xp));
    if (activity.length > 200) activity.removeRange(200, activity.length);
  }

  List<AchievementDef> _checkAchievements() {
    final out = <AchievementDef>[];
    for (final a in kAchievements) {
      if (achievements.contains(a.id)) continue;
      if (a.check(this)) {
        achievements.add(a.id);
        coins += a.coinReward;
        out.add(a);
        _log('achievement', 'دستاورد: ${a.nameFa}', 'Achievement: ${a.nameEn}');
      }
    }
    return out;
  }

  /// Wipe local identity (account deletion, P27).
  Future<void> resetAll() async {
    await _store.remove(_key);
    equipped.clear();
    inventory.clear();
    achievements.clear();
    stats.clear();
    activity.clear();
    counters.clear();
    decorLayout.clear();
    username = '';
    bio = '';
    xp = 0;
    coins = 0;
    crystals = 0;
    _load();
    notifyListeners();
  }
}

final profileProvider = ChangeNotifierProvider<ProfileService>((ref) => ProfileService(LocalStore.instance));
