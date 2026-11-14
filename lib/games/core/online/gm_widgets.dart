/// Shared chrome for online arcade matches: player strip with turn glow, countdown, result overlay.
library;

import 'package:flutter/material.dart';

import 'package:nexora/core/settings/app_settings.dart';
import 'package:nexora/core/theme/nx_theme.dart';

import 'gm_match_controller.dart';
import 'gm_models.dart';

const List<Color> kGmSeatColors = <Color>[
  NxColors.turquoise,
  NxColors.pink,
  NxColors.gold,
  NxColors.violet,
  NxColors.electricBlue,
  NxColors.success,
  Color(0xFFFF8A3D),
  Color(0xFF9BE15D),
  Color(0xFFB98BFF),
  Color(0xFF5AD1FF),
  Color(0xFFFF7AA8),
  Color(0xFFE0E0E0),
];

Color gmSeatColor(int seat) => kGmSeatColors[seat % kGmSeatColors.length];

String gmFaDigits(String s) {
  const String fa = '۰۱۲۳۴۵۶۷۸۹';
  final StringBuffer b = StringBuffer();
  for (final int c in s.codeUnits) {
    if (c >= 48 && c <= 57) {
      b.write(fa[c - 48]);
    } else {
      b.writeCharCode(c);
    }
  }
  return b.toString();
}

String gmNum(BuildContext context, int v) => context.isFa ? gmFaDigits('$v') : '$v';

/// Countdown chip for the current deadline.
class GmClock extends StatelessWidget {
  const GmClock({super.key, required this.c, this.total = const Duration(seconds: 30), this.compact = false});
  final GmMatchController c;
  final Duration total;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final GmView? v = c.view;
    if (v == null || !v.live || v.deadline == null) return const SizedBox.shrink();
    final int secs = (c.remaining.inMilliseconds / 1000).ceil();
    final double f = c.remainingFraction(total);
    final Color col = secs <= 5 ? NxColors.danger : (secs <= 10 ? NxColors.gold : NxColors.turquoise);
    final double size = compact ? 30 : 40;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(alignment: Alignment.center, children: <Widget>[
        SizedBox(
          width: size,
          height: size,
          child: CircularProgressIndicator(
            value: f,
            strokeWidth: 3,
            color: col,
            backgroundColor: Colors.white12,
          ),
        ),
        Text(gmNum(context, secs),
            style: TextStyle(fontSize: compact ? 11 : 13, fontWeight: FontWeight.w800, color: col)),
      ]),
    );
  }
}

/// One chip per seat: name, turn glow, idle strikes, out, optional extra line.
class GmPlayerStrip extends StatelessWidget {
  const GmPlayerStrip({super.key, required this.c, this.extra, this.colorOf, this.highlight});
  final GmMatchController c;

  /// Extra text under the name (score, cards left, …).
  final String? Function(int seat)? extra;
  final Color Function(int seat)? colorOf;

  /// Which seat glows (defaults to the turn seat).
  final int? highlight;

  @override
  Widget build(BuildContext context) {
    final GmView? v = c.view;
    if (v == null) return const SizedBox.shrink();
    final int hl = highlight ?? (v.live ? v.turn : -1);
    return SizedBox(
      height: 58,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: v.seatCount,
        separatorBuilder: (BuildContext _, int __) => const SizedBox(width: 6),
        itemBuilder: (BuildContext context, int s) {
          final Color col = colorOf?.call(s) ?? gmSeatColor(s);
          final bool on = s == hl;
          final bool out = v.isOut(s);
          final bool me = s == v.mySeat;
          final String? x = extra?.call(s);
          final int strikes = v.strikesOf(s);
          return AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: on ? col.withValues(alpha: 0.22) : Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: on ? col : Colors.white24, width: on ? 2 : 1),
              boxShadow: on ? <BoxShadow>[BoxShadow(color: col.withValues(alpha: 0.45), blurRadius: 12)] : null,
            ),
            child: Opacity(
              opacity: out ? 0.4 : 1,
              child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                CircleAvatar(radius: 9, backgroundColor: col, child: me ? const Icon(Icons.person, size: 12, color: Colors.black) : null),
                const SizedBox(width: 6),
                Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 110),
                    child: Text(
                      v.nameOf(s) + (me ? context.tx(' (تو)', ' (you)') : ''),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, decoration: out ? TextDecoration.lineThrough : null),
                    ),
                  ),
                  if (x != null || strikes > 0)
                    Text(
                      <String>[if (x != null) x, if (strikes > 0 && !out) '⏱×${gmNum(context, strikes)}'].join('  '),
                      style: const TextStyle(fontSize: 11, color: NxColors.textDim),
                    ),
                ]),
              ]),
            ),
          );
        },
      ),
    );
  }
}

/// Top bar: back, title, connection dot, clock, resign.
class GmTopBar extends StatelessWidget {
  const GmTopBar({super.key, required this.c, required this.title, required this.onBack, this.total = const Duration(seconds: 30)});
  final GmMatchController c;
  final String title;
  final VoidCallback onBack;
  final Duration total;

  Future<void> _confirmResign(BuildContext context) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(ctx.tx('تسلیم می‌شوی؟', 'Resign?')),
        content: Text(ctx.tx('این بازی را می‌بازی و از مسابقه خارج می‌شوی.', 'You lose this match and leave the table.')),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tx('ادامه', 'Keep playing'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tx('تسلیم', 'Resign'))),
        ],
      ),
    );
    if (ok == true) await c.resign();
  }

  @override
  Widget build(BuildContext context) {
    final GmView? v = c.view;
    final bool canResign = v != null && v.live && v.isPlayer && !v.isOut(v.mySeat!);
    return SizedBox(
      height: 52,
      child: Row(children: <Widget>[
        IconButton(onPressed: onBack, icon: const Icon(Icons.arrow_back_rounded)),
        Expanded(
          child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        ),
        Icon(Icons.circle, size: 9, color: c.connected ? NxColors.success : NxColors.gold),
        const SizedBox(width: 8),
        GmClock(c: c, total: total),
        if (canResign)
          IconButton(
            tooltip: context.tx('تسلیم', 'Resign'),
            onPressed: () => _confirmResign(context),
            icon: const Icon(Icons.flag_rounded, color: NxColors.danger),
          ),
      ]),
    );
  }
}

/// Error line shown under the board for a few seconds.
class GmErrorLine extends StatelessWidget {
  const GmErrorLine({super.key, required this.c});
  final GmMatchController c;

  @override
  Widget build(BuildContext context) {
    final String? e = c.error;
    if (e == null) return const SizedBox.shrink();
    return GestureDetector(
      onTap: c.clearError,
      child: Container(
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: NxColors.danger.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: NxColors.danger.withValues(alpha: 0.6)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
          const Icon(Icons.error_outline, size: 16, color: NxColors.danger),
          const SizedBox(width: 6),
          Flexible(child: Text(e, style: const TextStyle(fontSize: 13))),
        ]),
      ),
    );
  }
}

/// End-of-match card: winners, my result, rating change.
class GmResultOverlay extends StatelessWidget {
  const GmResultOverlay({super.key, required this.v, required this.onBack, this.detail});
  final GmView v;
  final VoidCallback onBack;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final int? o = v.myOutcome;
    final String head;
    final Color col;
    if (v.abandoned) {
      head = context.tx('بازی نیمه‌کاره ماند', 'Match abandoned');
      col = NxColors.gold;
    } else if (o == 1) {
      head = context.tx('بردی!', 'You won!');
      col = NxColors.success;
    } else if (o == -1) {
      head = context.tx('باختی', 'You lost');
      col = NxColors.danger;
    } else if (o == 0) {
      head = context.tx('مساوی', 'Draw');
      col = NxColors.gold;
    } else {
      head = context.tx('بازی تمام شد', 'Match over');
      col = NxColors.electricBlue;
    }
    final List<int> w = v.winners;
    final int? d = v.myRatingDelta;
    return Container(
      color: Colors.black.withValues(alpha: 0.62),
      alignment: Alignment.center,
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(22),
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: NxColors.navySoft.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: col, width: 2),
          boxShadow: <BoxShadow>[BoxShadow(color: col.withValues(alpha: 0.4), blurRadius: 30)],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Icon(o == 1 ? Icons.emoji_events_rounded : Icons.sports_esports_rounded, size: 54, color: col),
          const SizedBox(height: 8),
          Text(head, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: col)),
          const SizedBox(height: 8),
          if (w.isNotEmpty && !v.abandoned)
            Text(
              context.tx('برنده: ', 'Winner: ') + w.map(v.nameOf).join(context.isFa ? '، ' : ', '),
              textAlign: TextAlign.center,
            ),
          if (detail != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(detail!, textAlign: TextAlign.center, style: const TextStyle(color: NxColors.textDim))),
          if (d != null && d != 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                context.tx('امتیاز رتبه: ', 'Rating: ') + (d > 0 ? '+' : '') + gmNum(context, d),
                style: TextStyle(fontWeight: FontWeight.w800, color: d > 0 ? NxColors.success : NxColors.danger),
              ),
            ),
          if (o != null && !v.abandoned)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                context.tx('XP و سکه به حساب آنلاینت اضافه شد', 'XP and coins were added to your online account'),
                style: const TextStyle(fontSize: 12, color: NxColors.textDim),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.meeting_room_rounded),
            label: Text(context.tx('بازگشت به اتاق', 'Back to the room')),
          ),
        ]),
      ),
    );
  }
}
