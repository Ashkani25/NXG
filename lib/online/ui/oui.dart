/// Shared look + helpers for the online screens (port of the Godot app's src/online/oui.gd and
/// ui_bits.gd) built on the NEXORA theme (NxBackground, GlassPanel, NxColors).
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/settings/app_settings.dart';
import '../../core/theme/nx_theme.dart';
import '../../core/widgets/nx_widgets.dart';
import '../online_core.dart';
import '../supabase_client.dart';
import 'online_strings.dart';

// ---------------------------------------------------------------- colors
class OC {
  OC._();
  static const Color cyan = NxColors.electricBlue;
  static const Color violet = NxColors.violet;
  static const Color gold = NxColors.gold;
  static const Color red = NxColors.danger;
  static const Color green = NxColors.success;
  static const Color orange = Color(0xFFFF9F43);
  static const Color sky = Color(0xFF6EC8FF);
  static const Color gem = Color(0xFF9FD8FF);
  static const Color text = NxColors.iceWhite;
  static const Color dim = NxColors.textDim;
  static const Color dim2 = Color(0x66EAF6FF);
  static const Color line = Color(0x14FFFFFF);
  static const Color rowBg = Color(0xCC0A102C);
}

// ---------------------------------------------------------------- text
extension OnlineTx on BuildContext {
  /// Godot I18n.t(key) for the current language.
  String ot(String key) {
    final List<String>? v = kOnlineStrings[key] ?? _extra[key];
    if (v == null) return key;
    return isFa ? v[0] : v[1];
  }

  /// I18n.t(key) % args — `%s` / `%d` replaced in order.
  String otf(String key, List<Object?> args) => fmtArgs(ot(key), args);

  /// numbers in the UI language (Persian digits in fa)
  String fn(num n) => isFa ? faNum(n) : enNum(n);
}

const Map<String, List<String>> _extra = <String, List<String>>{
  'arena.find_opponent': <String>['پیدا کردن حریف', 'Find opponent'],
};

String fmtArgs(String s, List<Object?> args) {
  int i = 0;
  return s.replaceAllMapped(RegExp(r'%[sd]'), (Match m) => i < args.length ? '${args[i++]}' : m[0]!);
}

String faDigits(String t) {
  final StringBuffer b = StringBuffer();
  for (final int c in t.runes) {
    b.writeCharCode(c >= 48 && c <= 57 ? 0x06F0 + c - 48 : c);
  }
  return b.toString();
}

String _group(int v, String sep) {
  final String d = v.abs().toString();
  final StringBuffer b = StringBuffer();
  for (int k = 0; k < d.length; k++) {
    if (k > 0 && (d.length - k) % 3 == 0) b.write(sep);
    b.write(d[k]);
  }
  return b.toString();
}

/// n.toLocaleString('fa-IR'): Persian digits, '٬' thousands separator, '−' minus
String faNum(num n) {
  final int v = n.round();
  return (v < 0 ? '−' : '') + faDigits(_group(v, '٬'));
}

String enNum(num n) {
  final int v = n.round();
  return (v < 0 ? '−' : '') + _group(v, ',');
}

String pad2(BuildContext c, int n) {
  final String s = n.toString().padLeft(2, '0');
  return c.isFa ? faDigits(s) : s;
}

double isoToUnix(Object? iso) {
  if (iso == null || '$iso'.isEmpty) return 0;
  final DateTime? d = DateTime.tryParse('$iso');
  return d == null ? 0 : d.millisecondsSinceEpoch / 1000.0;
}

double nowS() => DateTime.now().millisecondsSinceEpoch / 1000.0;

String timeAgo(BuildContext c, Object? iso) {
  if (iso == null || '$iso'.isEmpty) return '';
  final double dt = nowS() - isoToUnix(iso);
  if (dt < 60) return c.ot('oui.now');
  if (dt < 3600) return c.otf('oui.x_min', <Object>[c.fn((dt / 60).floor())]);
  if (dt < 86400) return c.otf('oui.x_h', <Object>[c.fn((dt / 3600).floor())]);
  return c.otf('oui.x_d', <Object>[c.fn((dt / 86400).floor())]);
}

int oi(Object? v, [int d = 0]) => v is num ? v.toInt() : (v == null ? d : int.tryParse('$v') ?? d);
String os(Object? v, [String d = '']) => v == null ? d : '$v';
Map<String, dynamic> om(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<dynamic> oa(Object? v) => v is List ? v : const <dynamic>[];

// ---------------------------------------------------------------- rules (shared with backend)
const List<String> kModes = <String>['1v1', '2v2', '3v3'];
const Map<String, List<String>> kModeFa = <String, List<String>>{
  '1v1': <String>['تک به تک', '1 vs 1'],
  '2v2': <String>['۲ به ۲', '2 vs 2'],
  '3v3': <String>['۳ به ۳', '3 vs 3'],
};
const Map<String, List<String>> kKindFa = <String, List<String>>{
  'casual': <String>['دوستانه', 'Friendly'],
  'quick': <String>['سریع', 'Quick'],
  'arena': <String>['آرنا', 'Arena'],
  'tournament': <String>['تورنمنت', 'Tournament'],
};
const Map<String, Color> kKindColor = <String, Color>{'casual': OC.green, 'quick': OC.cyan, 'arena': OC.violet, 'tournament': OC.orange};
const List<List<String>> kRules = <List<String>>[
  <String>['g3', 'تا ۳ گل', 'First to 3'],
  <String>['g5', 'تا ۵ گل', 'First to 5'],
  <String>['t3', '۳ دقیقه', '3 min'],
  <String>['t5', '۵ دقیقه', '5 min'],
];
const List<List<Object>> kTurns = <List<Object>>[
  <Object>[10, '۱۰ث', '10s'],
  <Object>[15, '۱۵ث', '15s'],
  <Object>[20, '۲۰ث', '20s'],
  <Object>[0, 'بدون', 'None'],
];

String modeLabel(BuildContext c, String m) => c.tx(kModeFa[m]?[0] ?? m, kModeFa[m]?[1] ?? m);

Map<String, dynamic> ruleToSettings(String r) {
  switch (r) {
    case 'g3':
      return <String, dynamic>{'goals': 3, 'time': 0};
    case 'g5':
      return <String, dynamic>{'goals': 5, 'time': 0};
    case 't5':
      return <String, dynamic>{'goals': 3, 'time': 300};
  }
  return <String, dynamic>{'goals': 3, 'time': 180};
}

String settingsToRule(Map<String, dynamic> st) {
  final double t = st['time'] is num ? (st['time'] as num).toDouble() : 0;
  final double g = st['goals'] is num ? (st['goals'] as num).toDouble() : 3;
  if (t >= 300) return 't5';
  if (t > 0) return 't3';
  if (g >= 5) return 'g5';
  return 'g3';
}

String ruleLabel(BuildContext c, Map<String, dynamic> st) {
  final double t = st['time'] is num ? (st['time'] as num).toDouble() : 0;
  if (t > 0) return c.otf('oui.x_min', <Object>[c.fn((t / 60).round())]);
  final int g = st['goals'] is num ? (st['goals'] as num).toInt() : 3;
  return c.otf('oui.first_to_x_goals', <Object>[c.fn(g > 0 ? g : 3)]);
}

// ---------------------------------------------------------------- leagues
Color leagueColor(Map<String, dynamic>? lg) {
  final String c = os(lg?['color']).replaceAll('#', '');
  if (c.length == 6) {
    final int? v = int.tryParse(c, radix: 16);
    if (v != null) return Color(0xFF000000 | v);
  }
  return OC.cyan;
}

/// [current, next] league for a rating
(Map<String, dynamic>?, Map<String, dynamic>?) leagueFor(int rating) {
  final List<Map<String, dynamic>> list = List<Map<String, dynamic>>.of(OnlineCore.instance.leagues)
    ..sort((Map<String, dynamic> a, Map<String, dynamic> b) => oi(a['sort']).compareTo(oi(b['sort'])));
  Map<String, dynamic>? cur, nxt;
  for (final Map<String, dynamic> l in list) {
    if (oi(l['min_rating']) <= rating) {
      cur = l;
    } else {
      nxt ??= l;
    }
  }
  return (cur, nxt);
}

IconData leagueIcon(Object? id) {
  switch (os(id)) {
    case 'diamond':
    case 'master':
      return Icons.shield_rounded;
    case 'legend':
      return Icons.workspace_premium_rounded;
  }
  return Icons.military_tech_rounded;
}

Color leagueTint(Object? id) {
  switch (os(id)) {
    case 'bronze':
      return const Color(0xFFE0954A);
    case 'silver':
      return const Color(0xFFD6E2F0);
    case 'gold':
      return OC.gold;
    case 'platinum':
      return const Color(0xFF7FF5E0);
    case 'diamond':
      return const Color(0xFF8AD8FF);
    case 'master':
      return const Color(0xFFC08BFF);
    case 'legend':
      return const Color(0xFFFF6FA0);
  }
  return OC.cyan;
}

Widget leagueBadge(Object? id, double size) => Icon(leagueIcon(id), size: size, color: leagueTint(id));

// ---------------------------------------------------------------- feedback
void buzz(String kind) {
  switch (kind) {
    case 'heavy':
      HapticFeedback.heavyImpact();
    case 'medium':
      HapticFeedback.mediumImpact();
    case 'success':
      HapticFeedback.mediumImpact();
    default:
      HapticFeedback.selectionClick();
  }
}

void otoast(BuildContext context, String msg, {bool err = false}) {
  final ScaffoldMessengerState? m = ScaffoldMessenger.maybeOf(context);
  if (m == null || msg.isEmpty) return;
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    content: Text(msg, style: const TextStyle(color: OC.text, fontWeight: FontWeight.w700)),
    backgroundColor: err ? const Color(0xF0501020) : const Color(0xF00E2A44),
    behavior: SnackBarBehavior.floating,
    duration: const Duration(milliseconds: 2400),
  ));
}

// ---------------------------------------------------------------- page scaffold
class OPage extends StatelessWidget {
  const OPage({
    super.key,
    required this.title,
    this.en = '',
    required this.body,
    this.accent = OC.cyan,
    this.actions = const <Widget>[],
    this.onRefresh,
    this.onBack,
    this.bottom,
  });
  final String title;
  final String en;
  final Widget body;
  final Color accent;
  final List<Widget> actions;
  final VoidCallback? onRefresh;
  final VoidCallback? onBack;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WorldPalette.hub.background.first,
      body: NxBackground(
        palette: WorldPalette.hub,
        child: SafeArea(
          child: Column(children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
              child: Row(children: <Widget>[
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, color: OC.text),
                  onPressed: onBack ?? () => Navigator.of(context).maybePop(),
                ),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: <Widget>[
                    if (en.isNotEmpty)
                      Text(en, style: TextStyle(color: accent, fontSize: 9, letterSpacing: 2, fontWeight: FontWeight.w800)),
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: OC.text, fontSize: 19, fontWeight: FontWeight.w900)),
                  ]),
                ),
                ...actions,
                if (onRefresh != null)
                  IconButton(icon: Icon(Icons.refresh_rounded, color: accent), onPressed: onRefresh),
              ]),
            ),
            Expanded(child: body),
            if (bottom != null) bottom!,
          ]),
        ),
      ),
    );
  }
}

/// Glass panel with an accent border (OUI.panel).
class OPanel extends StatelessWidget {
  const OPanel({super.key, required this.child, this.accent, this.glow = false, this.pad = 12, this.onTap});
  final Widget child;
  final Color? accent;
  final bool glow;
  final double pad;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color b = accent ?? OC.line;
    final Widget p = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: glow && accent != null ? <BoxShadow>[BoxShadow(color: accent!.withValues(alpha: .28), blurRadius: 18)] : null,
      ),
      child: GlassPanel(
        padding: EdgeInsets.all(pad),
        radius: 18,
        tint: accent != null ? accent!.withValues(alpha: .07) : const Color(0x1AFFFFFF),
        borderColor: accent != null ? b.withValues(alpha: .55) : OC.line,
        blur: false,
        onTap: onTap,
        child: child,
      ),
    );
    return p;
  }
}

enum OBtnStyle { primary, green, gold, red, dark, violet }

class OBtn extends StatelessWidget {
  const OBtn(this.label, {super.key, this.onTap, this.style = OBtnStyle.primary, this.small = false, this.sub = '', this.busy = false});
  final String label;
  final VoidCallback? onTap;
  final OBtnStyle style;
  final bool small;
  final String sub;
  final bool busy;

  List<Color> get _cols {
    switch (style) {
      case OBtnStyle.primary:
        return const <Color>[Color(0xFF00C2FF), Color(0xFF3A6BFF)];
      case OBtnStyle.green:
        return const <Color>[Color(0xFF3DDC97), Color(0xFF14A06A)];
      case OBtnStyle.gold:
        return const <Color>[Color(0xFFFFD36B), Color(0xFFE09A1F)];
      case OBtnStyle.red:
        return const <Color>[Color(0xFFFF5A6E), Color(0xFFC0263D)];
      case OBtnStyle.violet:
        return const <Color>[Color(0xFF9D6BFF), Color(0xFF6A35E0)];
      case OBtnStyle.dark:
        return const <Color>[Color(0xFF1A2350), Color(0xFF111838)];
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool off = onTap == null || busy;
    final Color fg = style == OBtnStyle.gold ? const Color(0xFF2A1A00) : OC.text;
    return Opacity(
      opacity: off && !busy ? .5 : 1,
      child: Container(
        constraints: BoxConstraints(minHeight: small ? 44 : 52),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: _cols),
          borderRadius: BorderRadius.circular(16),
          border: style == OBtnStyle.dark ? Border.all(color: const Color(0x33FFFFFF)) : null,
          boxShadow: style == OBtnStyle.dark ? null : <BoxShadow>[BoxShadow(color: _cols[0].withValues(alpha: .35), blurRadius: 12)],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: off
                ? null
                : () {
                    buzz('light');
                    onTap!();
                  },
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: small ? 10 : 16, vertical: 6),
              child: Center(
                child: busy
                    ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: fg))
                    : Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                        Text(label,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: fg, fontWeight: FontWeight.w900, fontSize: small ? 13 : 15)),
                        if (sub.isNotEmpty)
                          Text(sub, style: TextStyle(color: fg.withValues(alpha: .75), fontSize: 10, fontWeight: FontWeight.w600)),
                      ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OBadge extends StatelessWidget {
  const OBadge(this.text, {super.key, this.color = OC.cyan, this.live = false});
  final String text;
  final Color color;
  final bool live;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .16),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: .5)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
          if (live) ...<Widget>[
            Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 4),
          ],
          Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800)),
        ]),
      );
}

/// Segmented control (OUI.segment). items: value → label.
class OSegment<T> extends StatelessWidget {
  const OSegment({super.key, required this.items, required this.value, required this.onChanged, this.accent = OC.cyan});
  final List<(T, String)> items;
  final T value;
  final ValueChanged<T> onChanged;
  final Color accent;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: const Color(0x99080C22), borderRadius: BorderRadius.circular(14), border: Border.all(color: OC.line)),
        child: Row(children: <Widget>[
          for (final (T, String) it in items)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  buzz('light');
                  onChanged(it.$1);
                },
                child: AnimatedContainer(
                  duration: NxMotion.fast,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: it.$1 == value ? accent.withValues(alpha: .22) : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: it.$1 == value ? accent.withValues(alpha: .7) : Colors.transparent),
                  ),
                  child: Text(it.$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: it.$1 == value ? OC.text : OC.dim, fontSize: 12, fontWeight: FontWeight.w800)),
                ),
              ),
            ),
        ]),
      );
}

class OBar extends StatelessWidget {
  const OBar(this.frac, {super.key, this.color = OC.cyan, this.color2, this.h = 8});
  final double frac;
  final Color color;
  final Color? color2;
  final double h;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(h),
        child: Container(
          height: h,
          color: const Color(0x1AFFFFFF),
          alignment: AlignmentDirectional.centerStart,
          child: FractionallySizedBox(
            widthFactor: frac.isNaN ? 0 : frac.clamp(0.0, 1.0),
            child: Container(decoration: BoxDecoration(gradient: LinearGradient(colors: <Color>[color, color2 ?? color]))),
          ),
        ),
      );
}

/// Power / accuracy mini bars (OUI.stat_bars compact).
class OStatBars extends StatelessWidget {
  const OStatBars({super.key, required this.power, required this.accuracy});
  final double power, accuracy;

  @override
  Widget build(BuildContext context) => Row(children: <Widget>[
        const Icon(Icons.bolt_rounded, size: 11, color: OC.orange),
        Expanded(child: OBar(power / 10, color: OC.orange, h: 4)),
        const SizedBox(width: 6),
        const Icon(Icons.gps_fixed_rounded, size: 10, color: OC.cyan),
        Expanded(child: OBar(accuracy / 10, color: OC.cyan, h: 4)),
      ]);
}

Widget oSpinner([double size = 28]) => Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(width: size, height: size, child: const CircularProgressIndicator(strokeWidth: 2.6, color: OC.cyan)),
      ),
    );

Widget oSkeleton([int rows = 4, double h = 72]) => Column(children: <Widget>[
      for (int i = 0; i < rows; i++)
        Container(
          height: h,
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(color: const Color(0x14FFFFFF), borderRadius: BorderRadius.circular(16)),
        ),
    ]);

class OEmpty extends StatelessWidget {
  const OEmpty({super.key, required this.icon, required this.title, this.sub = '', this.action = '', this.onAction});
  final IconData icon;
  final String title, sub, action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Icon(icon, size: 54, color: OC.cyan.withValues(alpha: .7)),
          const SizedBox(height: 10),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(color: OC.text, fontWeight: FontWeight.w800, fontSize: 15)),
          if (sub.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Text(sub, textAlign: TextAlign.center, style: const TextStyle(color: OC.dim, fontSize: 12)),
          ],
          if (action.isNotEmpty && onAction != null) ...<Widget>[
            const SizedBox(height: 14),
            OBtn(action, onTap: onAction, small: true),
          ],
        ]),
      );
}

class OError extends StatelessWidget {
  const OError(this.msg, {super.key, this.onRetry});
  final String msg;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          const Icon(Icons.cloud_off_rounded, size: 48, color: OC.red),
          const SizedBox(height: 10),
          Text(msg, textAlign: TextAlign.center, style: const TextStyle(color: OC.text, fontSize: 13)),
          if (onRetry != null) ...<Widget>[
            const SizedBox(height: 12),
            OBtn(context.tx('تلاش دوباره', 'Retry'), onTap: onRetry, small: true, style: OBtnStyle.dark),
          ],
        ]),
      );
}

Widget oCap(String t) => Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Text(t, style: const TextStyle(color: OC.dim, fontSize: 12, fontWeight: FontWeight.w800)),
    );

Widget oSection(String t) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 6),
      child: Text(t, style: const TextStyle(color: OC.text, fontSize: 16, fontWeight: FontWeight.w900)),
    );

/// Bottom sheet in the online look (OUI.open_sheet).
Future<T?> showOSheet<T>(BuildContext context, {required String title, String en = '', Color accent = OC.cyan, required WidgetBuilder builder}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * .9),
        decoration: BoxDecoration(
          color: const Color(0xF50A0F2C),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          border: Border.all(color: accent.withValues(alpha: .45)),
        ),
        child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
            const SizedBox(height: 8),
            Center(child: Container(width: 44, height: 4, decoration: BoxDecoration(color: OC.dim2, borderRadius: BorderRadius.circular(4)))),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                if (en.isNotEmpty) Text(en, style: TextStyle(color: accent, fontSize: 9, letterSpacing: 2, fontWeight: FontWeight.w800)),
                Text(title, style: const TextStyle(color: OC.text, fontSize: 18, fontWeight: FontWeight.w900)),
              ]),
            ),
            Flexible(child: builder(ctx)),
          ]),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------- avatar (NetImg.avatar)
/// "club0" / "club00" team id → "club00" art key (RN discImg / OUI.disc_key)
String discArtKey(Object? key) {
  final Match? m = RegExp(r'^([a-z]+)(\d+)$').firstMatch(os(key));
  if (m == null) return 'club00';
  return '${m.group(1)}${int.parse(m.group(2)!).toString().padLeft(2, '0')}';
}

class OAvatar extends StatelessWidget {
  const OAvatar({super.key, this.disc, this.url, this.size = 40, this.ring = OC.cyan, this.dim = false, this.dot});
  final Object? disc;
  final Object? url;
  final double size;
  final Color ring;
  final bool dim;
  final Color? dot;

  @override
  Widget build(BuildContext context) {
    final String u = os(url);
    final String k = discArtKey(disc);
    final Widget fallback = Container(
      color: const Color(0xFF16204F),
      alignment: Alignment.center,
      child: Icon(Icons.person_rounded, color: ring.withValues(alpha: .8), size: size * .6),
    );
    final Widget img = u.startsWith('http')
        ? Image.network(u, fit: BoxFit.cover, cacheWidth: (size * 3).round(), errorBuilder: (_, __, ___) => fallback)
        : Image.asset('assets/games/disc_football/teams/$k.webp',
            fit: BoxFit.cover, cacheWidth: (size * 3).round(), errorBuilder: (_, __, ___) => fallback);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(clipBehavior: Clip.none, children: <Widget>[
        Container(
          width: size,
          height: size,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ring, width: 2)),
          child: ClipOval(child: Opacity(opacity: dim ? .45 : 1, child: img)),
        ),
        if (dot != null)
          PositionedDirectional(
            end: 0,
            bottom: 0,
            child: Container(
              width: size * .26,
              height: size * .26,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle, border: Border.all(color: const Color(0xFF0A0F2C), width: 2)),
            ),
          ),
      ]),
    );
  }
}

/// Small helper: run [f] with a busy key and a toast on error (OUI pattern).
Future<OnlineResult> runRpc(BuildContext context, String fn, Map<String, dynamic> args, {String okMsg = ''}) async {
  final OnlineResult r = await callRpc(fn, args);
  if (!context.mounted) return r;
  if (r.ok) {
    if (okMsg.isNotEmpty) otoast(context, okMsg);
  } else {
    otoast(context, r.error, err: true);
    buzz('heavy');
  }
  return r;
}

/// periodic rebuild helper for countdowns
class OTicker extends StatefulWidget {
  const OTicker({super.key, required this.every, required this.builder});
  final Duration every;
  final WidgetBuilder builder;

  @override
  State<OTicker> createState() => _OTickerState();
}

class _OTickerState extends State<OTicker> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(widget.every, (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}

/// level progress record from supabase_client
({int level, int cur, int need, double frac}) lvl(Object? xp) => levelProgress(oi(xp));

double clamp01(double v) => math.min(1, math.max(0, v));
