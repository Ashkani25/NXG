/// Full-screen online match: top bar + the game's online board + result overlay.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:nexora/core/settings/app_settings.dart';
import 'package:nexora/core/theme/nx_theme.dart';
import 'package:nexora/core/widgets/nx_widgets.dart';
import 'package:nexora/online/online_core.dart';
import 'package:nexora/online/supabase_client.dart';

import 'gm_backend.dart';
import 'gm_boards.dart';
import 'gm_match_controller.dart';
import 'gm_models.dart';
import 'gm_widgets.dart';

/// Clock length per game / phase (matches the server's deadlines).
Duration gmClockTotal(GmView v) {
  switch (v.game) {
    case 'backgammon':
      return const Duration(seconds: 60);
    case 'ludo':
      return const Duration(seconds: 25);
    case 'snakes_ladders':
      return const Duration(seconds: 20);
    case 'uno':
      return const Duration(seconds: 30);
    case 'quiz':
      return Duration(seconds: v.phase == 'reveal' ? 4 : 15);
    case 'mafia':
      switch (v.phase) {
        case 'night':
          return const Duration(seconds: 40);
        case 'day':
          return const Duration(seconds: 90);
        case 'final':
          return const Duration(seconds: 20);
        default:
          return const Duration(seconds: 30);
      }
    default:
      return const Duration(seconds: 45);
  }
}

class GmMatchScreen extends StatefulWidget {
  const GmMatchScreen({
    super.key,
    required this.gameId,
    required this.matchId,
    required this.onBack,
    this.backend,
  });

  final String gameId;
  final String matchId;

  /// Back to the room (after the result, or the user leaves the screen).
  final VoidCallback onBack;
  final GmBackend? backend;

  @override
  State<GmMatchScreen> createState() => _GmMatchScreenState();
}

class _GmMatchScreenState extends State<GmMatchScreen> {
  late final GmMatchController _c;
  StreamSubscription<double>? _resume;
  bool _fa = true;

  @override
  void initState() {
    super.initState();
    _c = GmMatchController(
      matchId: widget.matchId,
      backend: widget.backend ?? const SupabaseGmBackend(),
      uid: OnlineCore.instance.uid,
      errorText: (Object e) => gmErrorText(errMessage(e), _fa),
    );
    _resume = OnlineCore.instance.resumed.listen((double _) => _c.refresh());
  }

  @override
  void dispose() {
    _resume?.cancel();
    _c.dispose();
    super.dispose();
  }

  Future<void> _back() async {
    final GmView? v = _c.view;
    if (v != null && v.live && v.isPlayer && !v.isOut(v.mySeat!)) {
      final bool? ok = await showDialog<bool>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          title: Text(ctx.tx('خروج از بازی؟', 'Leave the match?')),
          content: Text(ctx.tx(
              'بازی ادامه دارد. اگر برنگردی، بعد از چند نوبت از بازی حذف می‌شوی.',
              'The match goes on. If you do not come back you are removed after a few idle turns.')),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tx('ماندن', 'Stay'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tx('خروج', 'Leave'))),
          ],
        ),
      );
      if (ok != true) return;
    }
    widget.onBack();
  }

  @override
  Widget build(BuildContext context) {
    _fa = context.isFa;
    final GmGameSpec? spec = gmSpec(widget.gameId);
    final String title = spec == null ? widget.gameId : context.tx(spec.nameFa, spec.nameEn);
    return AnimatedBuilder(
      animation: _c,
      builder: (BuildContext context, Widget? _) {
        final GmView? v = _c.view;
        Widget body;
        if (v == null) {
          body = Center(
            child: _c.error == null
                ? const CircularProgressIndicator()
                : Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                    Text(_c.error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _c.refresh, child: Text(context.tx('تلاش دوباره', 'Retry'))),
                  ]),
          );
        } else {
          body = buildGmBoard(context, widget.gameId, _c);
        }
        return Stack(children: <Widget>[
          Positioned.fill(
            child: Column(children: <Widget>[
              SafeArea(
                bottom: false,
                child: GmTopBar(
                  c: _c,
                  title: title,
                  onBack: _back,
                  total: v == null ? const Duration(seconds: 30) : gmClockTotal(v),
                ),
              ),
              Expanded(child: body),
              SafeArea(top: false, child: GmErrorLine(c: _c)),
            ]),
          ),
          if (v != null && !v.live)
            Positioned.fill(
              child: GmResultOverlay(v: v, onBack: widget.onBack, detail: gmResultDetail(context, v)),
            ),
        ]);
      },
    );
  }
}

/// Plain full-screen wrapper (own background) used by the room page.
class GmMatchPage extends StatelessWidget {
  const GmMatchPage({super.key, required this.gameId, required this.matchId, required this.onBack});
  final String gameId;
  final String matchId;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NxColors.navyDeep,
      body: NxBackground(
        palette: WorldPalette.arcade,
        child: GmMatchScreen(gameId: gameId, matchId: matchId, onBack: onBack),
      ),
    );
  }
}
