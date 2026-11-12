/// Live Supabase backend shared with the Expo NEXORA app (same project, same accounts).
///
/// URL / anon key default to the public values the Expo app ships (src/net/publicConfig.ts).
/// The anon key is public by design: Row Level Security decides what it can do.
/// Override at build time with
///   --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const String kPublicSupabaseUrl = 'https://eisstodgncimypdawisy.supabase.co';
const String kPublicSupabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVpc3N0b2RnbmNpbXlwZGF3aXN5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTQyMjkwMTAsImV4cCI6MjEwOTgwNTAxMH0.uEPldAQjJdRyZTGXaz_OpFR7WpFXMiPXlW1S34cR3p8';

const String _envUrl = String.fromEnvironment('SUPABASE_URL');
const String _envKey = String.fromEnvironment('SUPABASE_ANON_KEY');

/// Deep-link redirect used by email confirmation / recovery links (same as Expo: nexora://auth).
const String kAuthRedirect = 'nexora://auth';

class Online {
  Online._();

  static String get url => _envUrl.isNotEmpty ? _envUrl : kPublicSupabaseUrl;
  static String get anonKey => _envKey.isNotEmpty ? _envKey : kPublicSupabaseAnonKey;
  static bool get configured => url.isNotEmpty && anonKey.isNotEmpty;

  static bool _ready = false;

  /// True once [init] succeeded. Widget tests and offline builds keep this false and every
  /// online screen shows a graceful "no connection" state instead of crashing.
  static bool get ready => _ready;

  /// Initialise once at startup. Never throws: with no network the app keeps working offline.
  static Future<void> init() async {
    if (_ready || !configured) return;
    try {
      await Supabase.initialize(
        url: url,
        anonKey: anonKey,
        authOptions: const FlutterAuthClientOptions(
          autoRefreshToken: true,
          // implicit flow: email links carry access_token/refresh_token in the URL fragment,
          // exactly what the Expo app parses, so links work across both clients and devices
          authFlowType: AuthFlowType.implicit,
          // email links are handled by our own deep-link parser (auth_links.dart), like the Expo app
          detectSessionInUri: false,
        ),
        realtimeClientOptions: const RealtimeClientOptions(logLevel: RealtimeLogLevel.error),
        debug: false,
      ).timeout(const Duration(seconds: 12));
      _ready = true;
    } catch (e) {
      debugPrint('NEXORA online init failed (offline mode): $e');
      _ready = false;
    }
  }

  static SupabaseClient get client {
    if (!_ready) throw const OnlineUnavailable();
    return Supabase.instance.client;
  }

  static String? get uid => _ready ? Supabase.instance.client.auth.currentUser?.id : null;
}

class OnlineUnavailable implements Exception {
  const OnlineUnavailable();
  @override
  String toString() => 'Network request failed: online backend unavailable';
}

/// rpc that throws on error (callers map errors with [errFa]) — same as `rpc()` in supabase.ts.
Future<T> rpc<T>(String fn, [Map<String, dynamic>? args]) async {
  final res = await Online.client.rpc(fn, params: args);
  return res as T;
}

/// Same as [rpc] but swallows every error (fire-and-forget calls like heartbeat / leave_room).
Future<void> rpcQuiet(String fn, [Map<String, dynamic>? args]) async {
  try {
    await rpc<dynamic>(fn, args);
  } catch (_) {}
}

// ---------- errors (1:1 with MAP / errFa in src/net/supabase.ts) ----------
final List<(RegExp, String)> _errMap = [
  (RegExp(r'not enough gems', caseSensitive: false), 'الماس کافی نداری'),
  (RegExp(r'already owned', caseSensitive: false), 'این دیسک را قبلاً داری'),
  (RegExp(r'not owned', caseSensitive: false), 'این دیسک را نداری'),
  (RegExp(r'already in club', caseSensitive: false), 'تو الان عضو یک باشگاه هستی'),
  (RegExp(r'club full', caseSensitive: false), 'ظرفیت باشگاه پر است'),
  (RegExp(r'invite only', caseSensitive: false), 'این باشگاه فقط با دعوت عضو می‌گیرد'),
  (RegExp(r'level too low', caseSensitive: false), 'سطحت برای این کار کافی نیست'),
  (RegExp(r'officer only', caseSensitive: false), 'فقط افسران باشگاه'),
  (RegExp(r'leader only', caseSensitive: false), 'فقط رهبر باشگاه'),
  (RegExp(r'admin only', caseSensitive: false), 'فقط مدیران'),
  (RegExp(r'already claimed', caseSensitive: false), 'قبلاً دریافت کردی'),
  (RegExp(r'not completed', caseSensitive: false), 'هنوز کامل نشده'),
  (RegExp(r'bad size', caseSensitive: false), 'اندازه‌ی نامعتبر'),
  (RegExp(r'already joined', caseSensitive: false), 'قبلاً ثبت‌نام کردی'),
  (RegExp(r'\bblocked\b', caseSensitive: false), 'این کاربر تو را مسدود کرده'),
  (RegExp(r'title required', caseSensitive: false), 'عنوان لازم است'),
  (RegExp(r'season running', caseSensitive: false), 'فصل هنوز تمام نشده'),
  (RegExp(r'cannot dm yourself', caseSensitive: false), 'نمی‌توانی به خودت پیام بدهی'),
  (RegExp(r'not public', caseSensitive: false), 'این گفتگو عمومی نیست'),
  (RegExp(r'club not found', caseSensitive: false), 'باشگاه پیدا نشد'),
  (RegExp(r'request not found', caseSensitive: false), 'درخواست پیدا نشد'),
  (RegExp(r'not allowed|bad action', caseSensitive: false), 'اجازه‌ی این کار را نداری'),
  (RegExp(r'clubs_name_key|duplicate key.*clubs.*name', caseSensitive: false), 'این نام باشگاه گرفته شده'),
  (RegExp(r'clubs_tag_key|duplicate key.*tag', caseSensitive: false), 'این تگ گرفته شده'),
  (RegExp(r'tag.*check|clubs_tag_check', caseSensitive: false), 'تگ باید ۲ تا ۵ حرف/عدد انگلیسی بزرگ باشد'),
  (RegExp(r'room not found', caseSensitive: false), 'اتاق پیدا نشد'),
  (RegExp(r'room closed', caseSensitive: false), 'این اتاق بسته شده'),
  (RegExp(r'teams not full', caseSensitive: false), 'هنوز همه‌ی جایگاه‌ها پر نشده'),
  (RegExp(r'not all ready', caseSensitive: false), 'همه‌ی بازیکن‌ها آماده نیستند'),
  (RegExp(r'seat taken', caseSensitive: false), 'این جایگاه گرفته شده'),
  (RegExp(r'host only', caseSensitive: false), 'فقط میزبان می‌تونه این کار رو بکنه'),
  (RegExp(r'organizer only', caseSensitive: false), 'فقط برگزارکننده می‌تونه این کار رو بکنه'),
  (RegExp(r'registration closed', caseSensitive: false), 'ثبت‌نام این تورنمنت بسته شده'),
  (RegExp(r'\bfull\b', caseSensitive: false), 'ظرفیت تکمیل است'),
  (RegExp(r'already started', caseSensitive: false), 'از قبل شروع شده'),
  (RegExp(r'match running', caseSensitive: false), 'بازی در جریان است'),
  (RegExp(r'match not live', caseSensitive: false), 'این مسابقه دیگر فعال نیست'),
  (RegExp(r'match not ready|not playable', caseSensitive: false), 'این مسابقه هنوز آماده نیست'),
  (RegExp(r'not in this match', caseSensitive: false), 'تو در این مسابقه نیستی'),
  (RegExp(r'need at least 2', caseSensitive: false), 'حداقل ۲ شرکت‌کننده لازم است'),
  (RegExp(r'bad slot', caseSensitive: false), 'جایگاه نامعتبر'),
  (RegExp(r'not signed in|JWT|unauthorized', caseSensitive: false), 'اول وارد حساب شو'),
  (RegExp(r'duplicate key.*username|profiles_username_key', caseSensitive: false), 'این نام کاربری قبلاً گرفته شده'),
  (RegExp(r'duplicate key.*tournament_entries|tournament_id, captain', caseSensitive: false), 'قبلاً در این تورنمنت ثبت‌نام کردی'),
  (RegExp(r'username.*check|char_length', caseSensitive: false), 'نام کاربری باید ۳ تا ۲۰ کاراکتر باشد'),
  (RegExp(r'Invalid login credentials', caseSensitive: false), 'ایمیل یا رمز عبور اشتباه است'),
  (RegExp(r'Email not confirmed', caseSensitive: false), 'ایمیلت هنوز تأیید نشده؛ صندوق ایمیل را ببین'),
  (RegExp(r'User already registered|already been registered|email_exists', caseSensitive: false), 'با این ایمیل قبلاً حساب ساخته شده'),
  (RegExp(r'Password should be at least|weak_password', caseSensitive: false), 'رمز عبور باید حداقل ۶ کاراکتر باشد'),
  (RegExp(r'rate limit|too many|over_email_send_rate_limit', caseSensitive: false), 'درخواست زیاد بود؛ کمی بعد دوباره امتحان کن'),
  (RegExp(r'invalid.*email|validate email|email_address_invalid', caseSensitive: false), 'ایمیل معتبر نیست'),
  (RegExp(r'Anonymous sign-ins are disabled', caseSensitive: false), 'ورود مهمان غیرفعال است'),
  // Expo patterns + the Dart/Flutter spellings of the same network failures
  (RegExp(r'Network request failed|Failed to fetch|fetch failed|timeout|NetworkError|SocketException|Failed host lookup|Connection refused|Connection closed|ClientException|HandshakeException|AuthRetryableFetchException',
      caseSensitive: false), 'اتصال اینترنت برقرار نیست'),
];

/// Raw message of any error the Supabase SDKs throw (PostgrestException, AuthException,
/// FunctionException, plain strings, …) — the Dart equivalent of `e.message || e.error_description || e.msg`.
String errMessage(Object? e) {
  if (e == null) return '';
  if (e is String) return e;
  if (e is PostgrestException) return [e.message, e.details, e.hint, e.code].whereType<Object>().map((x) => '$x').where((x) => x.isNotEmpty).join(' ');
  if (e is AuthException) return [e.message, e.code].whereType<String>().join(' ');
  if (e is FunctionException) {
    final d = e.details;
    if (d is Map) return '${d['error'] ?? d['message'] ?? d}';
    return '${d ?? e.reasonPhrase ?? e.status}';
  }
  if (e is Map) return '${e['message'] ?? e['error_description'] ?? e['msg'] ?? ''}';
  if (e is TimeoutException) return 'timeout';
  final s = e.toString();
  return s.startsWith('Exception: ') ? s.substring(11) : s;
}

/// Persian, user-facing error text. Identical mapping to errFa() in src/net/supabase.ts.
String errFa(Object? e) {
  final m = errMessage(e);
  for (final (re, fa) in _errMap) {
    if (re.hasMatch(m)) return fa;
  }
  if (m.isEmpty) return 'خطای ناشناخته؛ دوباره امتحان کن';
  return 'خطا: ${m.length > 80 ? m.substring(0, 80) : m}';
}

// ---------- level formula shared with the backend ----------
int teamSize(String mode) => mode == '1v1' ? 1 : mode == '2v2' ? 2 : 3;
int xpForLevel(int l) => (l < 1 ? 0 : (l - 1) * (l - 1)) * 100;
int levelOf(num xp) {
  final x = xp < 0 ? 0 : xp;
  final l = math.sqrt(x / 100).floor() + 1;
  return l < 1 ? 1 : l;
}

({int level, int cur, int need, double frac}) levelProgress(num xp) {
  final l = levelOf(xp);
  final a = xpForLevel(l), b = xpForLevel(l + 1);
  final cur = xp.toInt() - a;
  return (level: l, cur: cur, need: b - a, frac: (b - a) == 0 ? 0 : cur / (b - a));
}
