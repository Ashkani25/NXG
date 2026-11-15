// Cups (tournament v3) pure logic, shared by the UI and the tests. The server (supabase/cups.sql) is the authority;
// these functions mirror its rules exactly so the bracket / series / prize the app shows are what the server does.
//   * single elimination, 2..64 players, bracket size = next power of two, byes go to the best seeds
//   * a pairing is a series of N games (1..9): clinched when the lead is bigger than the games left; after N games a
//     tie on wins goes to goal difference, then sudden-death deciders; after N+3 games the higher seed advances
//   * legacy 0..100 gem escrow plus optional real-prize metadata with organizer-recorded manual settlement
//   * times are stored in UTC and shown in the Persian (Jalali) calendar, Tehran time (UTC+03:30, no DST since 2022)

/// Lineup window before each game; players can set their team and formation while this counts down.
/// Keep in sync with cup_cfg().lineup_s in supabase/cups.sql.
const int kCupLineupSeconds = 30;

/// Pause after a game before the next lineup window (server cup_cfg().gap_s).
const int kCupGapSeconds = 12;
const int kCupCheckinMinutes = 10; // check-in opens and the reminder is issued 10 minutes before start
const int kCupReminderMinutes = 10;
const int kCupReplaceMinutes = 5; // last minutes in which waitlisted players replace absentees
const int kCupNoShowMinutes = 5; // a player who does not enter a ready pairing in time loses by walkover
const int kCupMaxPlayers = 64;
const int kCupMaxPrize = 100;
const int kCupMaxGames = 9;
const int kCupGameMinutes = 6, kCupBufferMinutes = 4;
const List<int> kCupDefaultSplit = [60, 30, 10];
const List<List<int>> kCupSplits = [
  [100, 0, 0],
  [70, 30, 0],
  [60, 30, 10],
  [50, 30, 20],
];

// ------------------------------------------------------------------ bracket
int bracketSize(int n) {
  var s = 2;
  while (s < n) {
    s *= 2;
  }
  return s;
}

int bracketRounds(int n) {
  var r = 1, s = 2;
  while (s < n) {
    s *= 2;
    r++;
  }
  return r;
}

/// Standard seed order: pairs (o[2i], o[2i+1]) meet in round 1; seed 1 and 2 can only meet in the final.
List<int> seedOrder(int size) {
  if (size < 2) return [1];
  var o = [1, 2];
  while (o.length < size) {
    final l = o.length;
    o = [for (final s in o) ...[s, 2 * l + 1 - s]];
  }
  return o;
}

/// Round-1 pairings for n players: (seedA, seedB) with seedB = null for a bye.
List<(int, int?)> firstRound(int n) {
  final size = bracketSize(n), o = seedOrder(size);
  return [for (var i = 0; i < size ~/ 2; i++) (o[2 * i], o[2 * i + 1] <= n ? o[2 * i + 1] : null)];
}

/// Minutes between round starts (one series + buffer), server _cup_slot_min.
int roundSlotMinutes(int games) => games * kCupGameMinutes + kCupBufferMinutes;

/// Simulates a whole bracket with a winner rule (by seed) and returns the seeds at places 1..3 (null = nobody),
/// the same way the server fills the bracket (byes advance, semi losers meet in the 3rd-place match).
List<int?> simulatePlaces(int n, int Function(int a, int b) winnerOf) {
  final size = bracketSize(n);
  var cur = <int?>[for (final p in firstRound(n)) ...[p.$1, p.$2]];
  List<int?> semiLosers = [];
  while (cur.length > 1) {
    final next = <int?>[];
    final losers = <int?>[];
    for (var i = 0; i < cur.length; i += 2) {
      final a = cur[i], b = cur[i + 1];
      if (a == null || b == null) {
        next.add(a ?? b);
        losers.add(null);
      } else {
        final w = winnerOf(a, b);
        next.add(w);
        losers.add(w == a ? b : a);
      }
    }
    if (cur.length == 4) semiLosers = losers;
    if (cur.length == 2) {
      final third = size >= 4
          ? (semiLosers.whereType<int>().length == 2 ? winnerOf(semiLosers[0]!, semiLosers[1]!) : semiLosers.whereType<int>().firstOrNull)
          : null;
      return [next.first, losers.first, third];
    }
    cur = next;
  }
  return [cur.first, null, null];
}

String roundNameFa(int round, int rounds, {bool third = false}) {
  if (third) return 'رده‌بندی';
  final left = rounds - round; // 0 = final
  return switch (left) {
    0 => 'فینال',
    1 => 'نیمه‌نهایی',
    2 => 'یک‌چهارم نهایی',
    3 => 'یک‌هشتم نهایی',
    _ => faDigits('دور $round'),
  };
}

// ------------------------------------------------------------------ series
/// 1 / 2 = that side won the series, 0 = play another game (server _cup_series_winner).
int seriesWinner(int games, int w1, int w2, int g1, int g2, int played) {
  final rem = games - played < 0 ? 0 : games - played;
  if (w1 > w2 + rem) return 1;
  if (w2 > w1 + rem) return 2;
  if (played >= games) {
    if (g1 > g2) return 1;
    if (g2 > g1) return 2;
    if (played >= games + 3) return 1;
  }
  return 0;
}

/// Configurable series rules mirrored by _cup_series_winner_v2 in Supabase.
/// Returns 1/2 for the winner, or 0 while the series still needs another game.
int configuredSeriesWinner(String mode, int games, int targetWins, int w1, int w2, int g1, int g2, int played) {
  if (mode == 'single') {
    if (played < 1) return 0;
    return g1 >= g2 ? 1 : 2;
  }
  if (mode == 'first_to') {
    if (w1 >= targetWins) return 1;
    if (w2 >= targetWins) return 2;
    if (played >= games) {
      if (w1 != w2) return w1 > w2 ? 1 : 2;
      if (g1 != g2) return g1 > g2 ? 1 : 2;
      if (played >= games + 3) return 1;
    }
    return 0;
  }
  if (mode == 'aggregate') {
    if (played < games) return 0;
    if (g1 != g2) return g1 > g2 ? 1 : 2;
    if (played >= games + 3) return 1;
    return 0;
  }
  return seriesWinner(games, w1, w2, g1, g2, played);
}

/// Applies a configured rule to game scores, returning (winner side, games used).
(int, int) playConfiguredSeries(String mode, int games, int targetWins, List<(int, int)> scores) {
  var w1 = 0, w2 = 0, g1 = 0, g2 = 0, played = 0;
  for (final (a, b) in scores) {
    played++;
    g1 += a;
    g2 += b;
    if (a > b) w1++;
    if (b > a) w2++;
    final winner = configuredSeriesWinner(mode, games, targetWins, w1, w2, g1, g2, played);
    if (winner != 0) return (winner, played);
  }
  return (0, played);
}

/// Plays a list of game scores through the series rule; returns (winner side, games used).
(int, int) playSeries(int games, List<(int, int)> scores) {
  var w1 = 0, w2 = 0, g1 = 0, g2 = 0, n = 0;
  for (final (a, b) in scores) {
    n++;
    g1 += a;
    g2 += b;
    if (a > b) w1++;
    if (b > a) w2++;
    final w = seriesWinner(games, w1, w2, g1, g2, n);
    if (w != 0) return (w, n);
  }
  return (0, n);
}

// ------------------------------------------------------------------ series v3 (v0.7.0, server _cup_series_winner_v3)
/// Number of regulation games of a format (deciders come after these).
int cupRegGames(String mode, int games) => switch (mode) { 'two_leg' => 2, 'single' => 1, _ => games };

/// One finished game of a pairing, from side 1's (p1's) point of view. [home1] = p1 was the home side (team 0).
class CupGame {
  final int g1, g2;
  final bool home1;
  const CupGame(this.g1, this.g2, {this.home1 = true});
}

/// Mirror of _cup_series_winner_v3: 1 / 2 = that side won the pairing, 0 = play another game.
///  * single: the one game's winner; first_to: first to [targetWins] wins (n = 2*target-1);
///  * aggregate (n games) / two_leg (2 legs): regulation goals; two_leg with [awayGoals]: then away goals;
///  * still level -> decider games (each won by its winner); after 3 deciders without a winner side 1 advances.
int seriesWinnerV3(String mode, int games, int targetWins, List<CupGame> played, {bool awayGoals = false}) {
  if (mode == 'legacy') {
    var w1 = 0, w2 = 0, g1 = 0, g2 = 0;
    for (final g in played) {
      g1 += g.g1;
      g2 += g.g2;
      if (g.g1 > g.g2) w1++;
      if (g.g2 > g.g1) w2++;
    }
    return seriesWinner(games, w1, w2, g1, g2, played.length);
  }
  final n = cupRegGames(mode, games);
  var w1 = 0, w2 = 0, rg1 = 0, rg2 = 0, a1 = 0, a2 = 0, dw1 = 0, dw2 = 0;
  for (var i = 0; i < played.length; i++) {
    final g = played[i];
    if (g.g1 > g.g2) w1++;
    if (g.g2 > g.g1) w2++;
    if (i < n) {
      rg1 += g.g1;
      rg2 += g.g2;
      if (!g.home1) a1 += g.g1; // p1 away
      if (g.home1) a2 += g.g2; // p2 away
    } else {
      if (g.g1 > g.g2) dw1++;
      if (g.g2 > g.g1) dw2++;
    }
  }
  final p = played.length;
  switch (mode) {
    case 'first_to':
      if (w1 >= targetWins) return 1;
      if (w2 >= targetWins) return 2;
      if (p < n) return 0;
      if (w1 != w2) return w1 > w2 ? 1 : 2;
    case 'single':
      if (p < 1) return 0;
      if (rg1 != rg2) return rg1 > rg2 ? 1 : 2;
    case 'aggregate':
    case 'two_leg':
      if (p < n) return 0;
      if (rg1 != rg2) return rg1 > rg2 ? 1 : 2;
      if (mode == 'two_leg' && awayGoals && a1 != a2) return a1 > a2 ? 1 : 2;
    default:
      throw ArgumentError('bad series mode $mode');
  }
  if (dw1 > dw2) return 1;
  if (dw2 > dw1) return 2;
  if (p >= n + 3) return 1;
  return 0;
}

/// Who is home (team 0, kicks off, shown at the bottom) in game [gameNo] (1-based): p1, except leg 2 of a two-leg tie.
int cupHomeSide(String mode, int gameNo) => mode == 'two_leg' && gameNo == 2 ? 2 : 1;

/// Is game [gameNo] a tiebreak decider, and how many goals does it need ([decider] 'golden_goal' -> 1).
bool cupIsDecider(String mode, int games, int gameNo) => mode != 'legacy' && gameNo > cupRegGames(mode, games);
int cupGoalsFor(String mode, int games, int goals, int gameNo, String decider) =>
    cupIsDecider(mode, games, gameNo) && decider == 'golden_goal' ? 1 : goals;

/// Plays scores through the v3 rule (home sides per [cupHomeSide]); returns (winner side, games used).
(int, int) playSeriesV3(String mode, int games, int targetWins, List<(int, int)> scores, {bool awayGoals = false}) {
  final done = <CupGame>[];
  for (final (a, b) in scores) {
    done.add(CupGame(a, b, home1: cupHomeSide(mode, done.length + 1) == 1));
    final w = seriesWinnerV3(mode, games, targetWins, done, awayGoals: awayGoals);
    if (w != 0) return (w, done.length);
  }
  return (0, done.length);
}

/// Persian one-line explanation of a format for the create sheet.
String cupFormatHelpFa(String mode, int games, int targetWins, {bool awayGoals = false, String decider = 'golden_goal'}) {
  final tie = decider == 'golden_goal' ? 'در تساوی، بازی گل طلایی (اولین گل برنده) تعیین‌کننده است.' : 'در تساوی، یک بازی کامل تعیین‌کننده برگزار می‌شود.';
  return switch (mode) {
    'single' => 'نتیجه‌ی همان یک بازی تعیین‌کننده است.',
    'first_to' => faDigits('هر بازیکنی که زودتر $targetWins برد بگیرد صعود می‌کند (حداکثر ${2 * targetWins - 1} بازی).'),
    'aggregate' => faDigits('برنده با مجموع گل‌های $games بازی مشخص می‌شود. ') + tie,
    'two_leg' => 'بازی رفت در خانه‌ی نفر اول و برگشت در خانه‌ی نفر دوم؛ مجموع گل دو بازی${awayGoals ? '، سپس گل خارج از خانه' : ' (گل خارج از خانه حساب نمی‌شود)'}. $tie',
    _ => formatFa(games),
  };
}

/// Cup room line for game [gameNo]: leg / decider / goals to win / who is home.
String cupGameLabelFa(String mode, int games, int goals, int gameNo, String decider, {bool meIsP1 = true}) {
  final g = cupGoalsFor(mode, games, goals, gameNo, decider);
  final dec = cupIsDecider(mode, games, gameNo);
  final home = cupHomeSide(mode, gameNo) == (meIsP1 ? 1 : 2);
  final head = dec
      ? (decider == 'golden_goal' ? 'تعیین‌کننده · گل طلایی' : 'بازی تعیین‌کننده')
      : mode == 'two_leg'
          ? (gameNo == 1 ? 'بازی رفت' : 'بازی برگشت')
          : faDigits('بازی $gameNo از ${cupRegGames(mode, games)}');
  return faDigits('$head · $g گل برنده است') + (mode == 'two_leg' && !dec ? (home ? ' · میزبان تویی' : ' · مهمانی') : '');
}

/// Arguments of the cup_create_v3 RPC (server validates everything again).
Map<String, Object?> cupCreateParams({required String name, required int max, required String mode, required int games, required int targetWins,
        required int goals, required DateTime startsUtc, int prize = 0, List<int> split = kCupDefaultSplit, bool play = true,
        bool requireApproval = false, bool awayGoals = false, String decider = 'golden_goal', String prizeTitle = '', double cash = 0, String currency = ''}) =>
    {
      'p_name': name, 'p_max': max, 'p_mode': mode,
      'p_games': mode == 'single' ? 1 : mode == 'two_leg' ? 2 : mode == 'first_to' ? 2 * targetWins - 1 : games,
      'p_target_wins': mode == 'first_to' ? targetWins : 1,
      'p_goals': goals, 'p_starts': startsUtc.toUtc().toIso8601String(), 'p_prize': prize, 'p_split': split, 'p_join': play,
      'p_require_approval': requireApproval, 'p_away_goals': mode == 'two_leg' && awayGoals, 'p_decider': decider,
      'p_prize_title': prizeTitle, 'p_cash_prize': cash, 'p_cash_currency': currency,
    };

// ------------------------------------------------------------------ lineup (30 s pre-match window, server cup_ready)
/// Seconds left on the pre-match lineup screen: the server deadline (lineup_until) when known, never more than
/// [kCupLineupSeconds] after the local Play press; 0 = use what is selected (or the defaults) now.
int lineupSecondsLeft({required DateTime now, required DateTime pressedAt, DateTime? serverUntil}) {
  final local = pressedAt.add(const Duration(seconds: kCupLineupSeconds));
  final until = serverUntil == null || serverUntil.isAfter(local) ? local : serverUntil;
  final ms = until.difference(now).inMilliseconds;
  if (ms <= 0) return 0;
  return ((ms + 999) ~/ 1000).clamp(0, kCupLineupSeconds);
}

/// What a player plays with when the lineup timer runs out: their pick, else the equipped team / formation 0 /
/// the room's pitch and ball.
({String team, int formation, int field, int ball}) lineupFinal({String? pickedTeam, int? pickedFormation, int? pickedField, int? pickedBall,
        required String equippedTeam, required int roomField, required int roomBall}) =>
    (team: pickedTeam ?? equippedTeam, formation: pickedFormation ?? 0, field: pickedField ?? roomField, ball: pickedBall ?? roomBall);

/// 'cupmatch:<cupId>:<matchId>' -> (cupId, matchId); null for anything else.
(String, String)? cupMatchEntry(String entry) {
  if (!entry.startsWith('cupmatch:')) return null;
  final p = entry.substring(9).split(':');
  if (p.length != 2 || p[0].isEmpty || p[1].isEmpty) return null;
  return (p[0], p[1]);
}

// ------------------------------------------------------------------ rankings (server _cup_rank_points)
int cupRankPoints({int titles = 0, int runnerUp = 0, int third = 0, int fourth = 0, int cups = 0, int seriesWins = 0}) =>
    25 * titles + 15 * runnerUp + 10 * third + 6 * fourth + 2 * cups + 3 * seriesWins;

String formatFa(int games) => switch (games) {
      1 => 'تک بازی',
      2 => 'دو بازی (مجموع)',
      _ => faDigits(games.isOdd ? 'بهترین $games' : '$games بازی (مجموع)'),
    };

String cupSeriesLabel(String mode, int games, int targetWins) => switch (mode) {
      'single' => 'تک‌بازی',
      'aggregate' => 'مجموع گل · ${faDigits(games.toString())} بازی',
      'first_to' => 'اول به ${faDigits(targetWins.toString())} برد · حداکثر ${faDigits(games.toString())} بازی',
      'two_leg' => 'رفت و برگشت · مجموع گل',
      _ => formatFa(games),
    };

// ------------------------------------------------------------------ prize
/// Gems for places 1..3 (server _cup_shares).
List<int> prizeShares(int prize, List<int> split) {
  final a = [for (var i = 0; i < 3; i++) prize * split[i] ~/ 100];
  a[0] += prize - a[0] - a[1] - a[2];
  return a;
}

bool validSplit(List<int> s) => s.length == 3 && s[2] >= 0 && s[0] >= s[1] && s[1] >= s[2] && s[0] + s[1] + s[2] == 100;

// ------------------------------------------------------------------ Jalali calendar + Tehran time
const Duration kTehranOffset = Duration(hours: 3, minutes: 30);
const kJalaliMonths = ['فروردین', 'اردیبهشت', 'خرداد', 'تیر', 'مرداد', 'شهریور', 'مهر', 'آبان', 'آذر', 'دی', 'بهمن', 'اسفند'];
// DateTime.weekday: 1 = Monday ... 7 = Sunday
const kFaWeekdays = {1: 'دوشنبه', 2: 'سه‌شنبه', 3: 'چهارشنبه', 4: 'پنجشنبه', 5: 'جمعه', 6: 'شنبه', 7: 'یکشنبه'};

(int, int, int) gregorianToJalali(int gy, int gm, int gd) {
  const gdm = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334];
  final gy2 = gm > 2 ? gy + 1 : gy;
  var days = 355666 + 365 * gy + (gy2 + 3) ~/ 4 - (gy2 + 99) ~/ 100 + (gy2 + 399) ~/ 400 + gd + gdm[gm - 1];
  var jy = -1595 + 33 * (days ~/ 12053);
  days %= 12053;
  jy += 4 * (days ~/ 1461);
  days %= 1461;
  if (days > 365) {
    jy += (days - 1) ~/ 365;
    days = (days - 1) % 365;
  }
  final jm = days < 186 ? 1 + days ~/ 31 : 7 + (days - 186) ~/ 30;
  final jd = days < 186 ? 1 + days % 31 : 1 + (days - 186) % 30;
  return (jy, jm, jd);
}

(int, int, int) jalaliToGregorian(int jy, int jm, int jd) {
  jy += 1595;
  var days = -355668 + 365 * jy + (jy ~/ 33) * 8 + ((jy % 33) + 3) ~/ 4 + jd + (jm < 7 ? (jm - 1) * 31 : (jm - 7) * 30 + 186);
  var gy = 400 * (days ~/ 146097);
  days %= 146097;
  if (days > 36524) {
    days--;
    gy += 100 * (days ~/ 36524);
    days %= 36524;
    if (days >= 365) days++;
  }
  gy += 4 * (days ~/ 1461);
  days %= 1461;
  if (days > 365) {
    gy += (days - 1) ~/ 365;
    days = (days - 1) % 365;
  }
  var gd = days + 1;
  final leap = (gy % 4 == 0 && gy % 100 != 0) || gy % 400 == 0;
  final ml = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  var gm = 0;
  while (gm < 12 && gd > ml[gm]) {
    gd -= ml[gm];
    gm++;
  }
  return (gy, gm + 1, gd);
}

/// Wall-clock Tehran fields of a UTC instant (returned as a UTC DateTime carrying Tehran's numbers).
DateTime tehranWall(DateTime t) => t.toUtc().add(kTehranOffset);

/// UTC instant of a Tehran wall-clock time given in the Jalali calendar.
DateTime fromTehranJalali(int jy, int jm, int jd, int hour, int minute) {
  final (gy, gm, gd) = jalaliToGregorian(jy, jm, jd);
  return DateTime.utc(gy, gm, gd, hour, minute).subtract(kTehranOffset);
}

String _two(int v) => v.toString().padLeft(2, '0');
String faDigits(String s) {
  const d = '۰۱۲۳۴۵۶۷۸۹';
  return s.replaceAllMapped(RegExp(r'[0-9]'), (m) => d[int.parse(m[0]!)]);
}

/// e.g. «شنبه ۲۴ آبان ۱۴۰۵ · ۱۸:۳۰» (Tehran time)
String jalaliLabel(DateTime utc, {bool year = false, bool weekday = true, bool time = true}) {
  final w = tehranWall(utc);
  final (jy, jm, jd) = gregorianToJalali(w.year, w.month, w.day);
  final parts = <String>[
    if (weekday) kFaWeekdays[w.weekday]!,
    '$jd ${kJalaliMonths[jm - 1]}${year ? ' $jy' : ''}',
  ];
  final s = parts.join(' ') + (time ? ' · ${_two(w.hour)}:${_two(w.minute)}' : '');
  return faDigits(s);
}

String tehranClock(DateTime utc) {
  final w = tehranWall(utc);
  return faDigits('${_two(w.hour)}:${_two(w.minute)}');
}

/// «۲ ساعت و ۵ دقیقه» / «۴۵ ثانیه»
String faCountdown(Duration d) {
  if (d.isNegative) return faDigits('0');
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  if (d.inDays >= 1) return faDigits('${d.inDays} روز و ${h % 24} ساعت');
  if (h > 0) return faDigits('$h ساعت و $m دقیقه');
  if (m > 0) return faDigits('$m دقیقه و $s ثانیه');
  return faDigits('$s ثانیه');
}
