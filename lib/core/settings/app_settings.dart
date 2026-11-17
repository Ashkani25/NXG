import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/local_store.dart';
import '../theme/nx_theme.dart';

enum GraphicsQuality { low, medium, high, ultra }

/// Global app settings (P13, P16, P28). Persisted locally.
class AppSettings extends ChangeNotifier {
  AppSettings(this._store) {
    final q = _store.getString(_kQuality);
    _quality = GraphicsQuality.values
        .firstWhere((e) => e.name == q, orElse: () => GraphicsQuality.high);
    _reducedMotion = _store.getBool(_kReduced) ?? false;
    _languageCode = _store.getString(_kLang) ?? 'fa';
    _visualTheme = NxVisualTheme.values.firstWhere(
      (e) => e.name == _store.getString(_kVisualTheme),
      orElse: () => NxVisualTheme.neon,
    );
    // NX2 redesign: the cosmic neon skin is the only app skin now.
    _visualTheme = NxVisualTheme.neon;
    _music = _store.getBool(_kMusic) ?? true;
    _musicVolume = (_store.getInt(_kMusicVol) ?? 60).clamp(0, 100) / 100.0;
    _sound = _store.getBool(_kSound) ?? true;
    _haptics = _store.getBool(_kHaptics) ?? true;
    _journeySeen = _store.getBool(_kJourney) ?? false;
    _onboarded = _store.getBool(_kOnboarded) ?? false;
    _authMode = _store.getString(_kAuthMode) ?? '';
    _oracleBuddy = _store.getBool(_kOracleBuddy) ?? true;
    _oracleTalk = _store.getBool(_kOracleTalk) ?? true;
    _themeMode = ThemeMode.values.firstWhere((e) => e.name == _store.getString(_kThemeMode),
        orElse: () => ThemeMode.dark);
    _highContrast = _store.getBool(_kHighContrast) ?? false;
    _fontScale = ((_store.getInt(_kFontScale) ?? 100) / 100.0).clamp(minFontScale, maxFontScale);
    _notifyInvites = _store.getBool(_kNotifyInvites) ?? true;
    _notifyTournaments = _store.getBool(_kNotifyTournaments) ?? true;
    _oracleOffline = _store.getBool(_kOracleOffline) ?? false;
    _favoriteGames = (_store.getString(_kFavoriteGames) ?? '')
        .split(',')
        .where((String e) => e.isNotEmpty)
        .toList();
  }

  static const _kFavoriteGames = 'settings.favorite_games';
  late List<String> _favoriteGames;

  /// Games picked in onboarding step 3 (shown first in the arcade). Empty = no preference.
  List<String> get favoriteGames => List<String>.unmodifiable(_favoriteGames);

  set favoriteGames(List<String> ids) {
    _favoriteGames = ids.toSet().toList();
    _store.setString(_kFavoriteGames, _favoriteGames.join(','));
    notifyListeners();
  }

  static const _kThemeMode = 'settings.theme_mode';
  static const _kHighContrast = 'settings.high_contrast';
  static const _kFontScale = 'settings.font_scale';
  static const _kNotifyInvites = 'settings.notify_invites';
  static const _kNotifyTournaments = 'settings.notify_tournaments';
  static const _kOracleOffline = 'settings.oracle_offline';
  static const double minFontScale = 0.85;
  static const double maxFontScale = 1.3;
  late ThemeMode _themeMode;
  late bool _highContrast;
  late double _fontScale;
  late bool _notifyInvites;
  late bool _notifyTournaments;
  late bool _oracleOffline;

  /// App theme: follow the system, or force dark / light. Games always stay dark.
  ThemeMode get themeMode => _themeMode;

  /// Light theme for the given platform brightness.
  bool isLight(Brightness platform) =>
      _themeMode == ThemeMode.light ||
      (_themeMode == ThemeMode.system && platform == Brightness.light);

  /// Accessibility: stronger text/borders.
  bool get highContrast => _highContrast;

  /// Accessibility: app-wide text size multiplier ([minFontScale]..[maxFontScale]).
  double get fontScale => _fontScale;

  /// Real-time game invitations from friends (InviteWatcher).
  bool get notifyInvites => _notifyInvites;

  /// Tournament alerts and 10-minute reminders (TournamentWatcher).
  bool get notifyTournaments => _notifyTournaments;

  /// ORACLE answers on this device only; nothing from the chat is sent to the cloud model.
  bool get oracleOffline => _oracleOffline;

  set themeMode(ThemeMode v) {
    if (_themeMode == v) return;
    _themeMode = v;
    _store.setString(_kThemeMode, v.name);
    notifyListeners();
  }

  set highContrast(bool v) {
    _highContrast = v;
    _store.setBool(_kHighContrast, v);
    notifyListeners();
  }

  set fontScale(double v) {
    _fontScale = v.clamp(minFontScale, maxFontScale);
    _store.setInt(_kFontScale, (_fontScale * 100).round());
    notifyListeners();
  }

  set notifyInvites(bool v) {
    _notifyInvites = v;
    _store.setBool(_kNotifyInvites, v);
    notifyListeners();
  }

  set notifyTournaments(bool v) {
    _notifyTournaments = v;
    _store.setBool(_kNotifyTournaments, v);
    notifyListeners();
  }

  set oracleOffline(bool v) {
    _oracleOffline = v;
    _store.setBool(_kOracleOffline, v);
    notifyListeners();
  }

  static const _kOracleBuddy = 'settings.oracle_buddy';
  static const _kOracleTalk = 'settings.oracle_talk';
  late bool _oracleBuddy;
  late bool _oracleTalk;

  /// The mischievous corner ORACLE outside games (off = hidden everywhere).
  bool get oracleBuddy => _oracleBuddy;

  /// Speech bubbles / teasing lines from the corner ORACLE (off = silent, animations only).
  bool get oracleTalk => _oracleTalk;

  set oracleBuddy(bool v) {
    _oracleBuddy = v;
    _store.setBool(_kOracleBuddy, v);
    notifyListeners();
  }

  set oracleTalk(bool v) {
    _oracleTalk = v;
    _store.setBool(_kOracleTalk, v);
    notifyListeners();
  }

  final LocalStore _store;
  static const _kQuality = 'settings.quality';
  static const _kReduced = 'settings.reduced_motion';
  static const _kLang = 'settings.lang';
  static const _kVisualTheme = 'settings.visual_theme';
  static const _kSound = 'settings.sound';
  static const _kHaptics = 'settings.haptics';
  static const _kJourney = 'settings.journey_seen';
  static const _kOnboarded = 'settings.onboarded';
  static const _kAuthMode = 'settings.auth_mode';
  static const _kMusic = 'settings.music';
  static const _kMusicVol = 'settings.music_volume';

  late GraphicsQuality _quality;
  late bool _reducedMotion;
  late String _languageCode;
  late NxVisualTheme _visualTheme;
  late bool _sound;
  late bool _haptics;
  late bool _journeySeen;
  late bool _onboarded;
  late String _authMode;
  late bool _music;
  late double _musicVolume;

  /// Background music on menus (default on).
  bool get music => _music;

  /// 0..1 background music volume.
  double get musicVolume => _musicVolume;

  set music(bool v) {
    _music = v;
    _store.setBool(_kMusic, v);
    notifyListeners();
  }

  set musicVolume(double v) {
    _musicVolume = v.clamp(0.0, 1.0);
    _store.setInt(_kMusicVol, (_musicVolume * 100).round());
    notifyListeners();
  }

  GraphicsQuality get quality => _quality;
  bool get reducedMotion => _reducedMotion;
  String get languageCode => _languageCode;
  NxVisualTheme get visualTheme => _visualTheme;
  bool get isFa => _languageCode == 'fa';
  Locale get locale => Locale(_languageCode);
  bool get sound => _sound;
  bool get haptics => _haptics;
  bool get journeySeen => _journeySeen;
  bool get onboarded => _onboarded;

  /// '', 'email' or 'guest'. Guest is deliberately local-only.
  String get authMode => _authMode;

  void setAuthMode(String mode) {
    if (mode != 'email' && mode != 'guest' && mode.isNotEmpty) return;
    _authMode = mode;
    _store.setString(_kAuthMode, mode);
    notifyListeners();
  }

  void clearAuthMode() => setAuthMode('');

  /// Effects budget helpers used by every world and game.
  bool get fancyEffects =>
      !_reducedMotion && _quality.index >= GraphicsQuality.medium.index;
  int get starCount => switch (_quality) {
        GraphicsQuality.low => 60,
        GraphicsQuality.medium => 140,
        GraphicsQuality.high => 240,
        GraphicsQuality.ultra => 380,
      };

  set quality(GraphicsQuality v) {
    _quality = v;
    _store.setString(_kQuality, v.name);
    notifyListeners();
  }

  set reducedMotion(bool v) {
    _reducedMotion = v;
    _store.setBool(_kReduced, v);
    notifyListeners();
  }

  set languageCode(String v) {
    _languageCode = v;
    _store.setString(_kLang, v);
    notifyListeners();
  }

  set visualTheme(NxVisualTheme v) {
    if (_visualTheme == v) return;
    _visualTheme = v;
    _store.setString(_kVisualTheme, v.name);
    notifyListeners();
  }

  set sound(bool v) {
    _sound = v;
    _store.setBool(_kSound, v);
    notifyListeners();
  }

  set haptics(bool v) {
    _haptics = v;
    _store.setBool(_kHaptics, v);
    notifyListeners();
  }

  void markJourneySeen() {
    _journeySeen = true;
    _store.setBool(_kJourney, true);
    notifyListeners();
  }

  void markOnboarded() {
    _onboarded = true;
    _store.setBool(_kOnboarded, true);
    notifyListeners();
  }
}

final settingsProvider = ChangeNotifierProvider<AppSettings>(
    (ref) => AppSettings(LocalStore.instance));

/// Bilingual text helper: `context.tx('سلام', 'Hello')`.
extension NxTx on BuildContext {
  bool get isFa => Localizations.localeOf(this).languageCode == 'fa';
  String tx(String fa, String en) => isFa ? fa : en;
}
