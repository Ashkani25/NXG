import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/audio/music_service.dart';
import '../../core/profile/profile_service.dart';
import '../../core/settings/app_settings.dart';
import '../../core/ui2/nx2_assets.dart';
import '../../core/ui2/nx2_widgets.dart';
import '../../core/ui2/oracle_mascot.dart';
import '../../core/widgets/nx_widgets.dart';

/// HOME tab (NX2 redesign, simplified in UI audit M1): profile HUD on top (avatar -> Profile, coins -> Shop,
/// gear -> Settings), ORACLE on its crystal dock, one big PLAY, ORACLE chat, today's reward when it is ready,
/// and the tournaments / latest-activity strip. Everything else lives in its own tab (docs/UI_AUDIT.md).
class HubPage extends ConsumerStatefulWidget {
  const HubPage({super.key});

  @override
  ConsumerState<HubPage> createState() => _HubPageState();
}

class _HubPageState extends ConsumerState<HubPage> {
  final ValueNotifier<int> _coinPoke = ValueNotifier<int>(0);
  OracleMood _mood = OracleMood.greet;
  int _line = 0;

  @override
  void initState() {
    super.initState();
    // Deep links skip the intro; make sure the menu music still starts.
    MusicService.instance.start();
    _calm = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _mood = OracleMood.idle);
    });
  }

  Timer? _calm;

  @override
  void dispose() {
    _calm?.cancel();
    _coinPoke.dispose();
    super.dispose();
  }

  List<(String, String)> _lines(ProfileService p) => <(String, String)>[
        (
          _greetFa(p.username),
          _greetEn(p.username),
        ),
        (
          'یک دست فوتبال انگشتی؟ من داور می‌شم! 😄',
          'Finger soccer? I will referee! 😄'
        ),
        (
          'نگهم داری، چیزهای باحال نشونت می‌دم.',
          'Long-press me and I will show you cool stuff.'
        ),
        if (p.canClaimDaily)
          (
            'صندوق جایزه‌ی امروز منتظرته! 🎁',
            'Today\'s reward chest is waiting! 🎁'
          ),
      ];

  String _greetFa(String n) {
    final int h = DateTime.now().hour;
    final String part = h < 12 ? 'صبح بخیر' : (h < 18 ? 'روز بخیر' : 'شب بخیر');
    return n.isEmpty ? '$part، کاوشگر!' : '$part، $n!';
  }

  String _greetEn(String n) {
    final int h = DateTime.now().hour;
    final String part =
        h < 12 ? 'Good morning' : (h < 18 ? 'Good afternoon' : 'Good evening');
    return n.isEmpty ? '$part, explorer!' : '$part, $n!';
  }

  Future<void> _claimDaily() async {
    final ProfileService p = ref.read(profileProvider);
    final AwardOutcome? o = p.claimDaily();
    if (!mounted) return;
    if (o == null) {
      setState(() => _mood = OracleMood.calm);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.tx('جایزه‌ی امروز را گرفته‌ای. فردا برگرد!',
              'Already claimed today. Come back tomorrow!'))));
      return;
    }
    setState(() => _mood = OracleMood.win);
    _coinPoke.value++;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tx('+${o.coins} سکه و +${o.xp} XP',
            '+${o.coins} coins and +${o.xp} XP'))));
    await showAwardOutcome(context, o);
  }

  @override
  Widget build(BuildContext context) {
    final ProfileService p = ref.watch(profileProvider);
    final List<(String, String)> lines = _lines(p);
    final (String, String) line = lines[_line % lines.length];
    return Scaffold(
      backgroundColor: Nx2.deep,
      extendBody: true,
      bottomNavigationBar: const Nx2Dock(current: Nx2Tab.home),
      body: Nx2Background(
        dim: 0.3,
        child: Stack(children: <Widget>[
          SafeArea(
            bottom: false,
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: <Widget>[
                SliverToBoxAdapter(
                    child: _Hud(profile: p, coinPoke: _coinPoke)),
                SliverToBoxAdapter(
                  child: _OracleStage(
                    mood: _mood,
                    textFa: line.$1,
                    textEn: line.$2,
                    onTap: () => setState(() {
                      _line++;
                      _mood = OracleMood.happy;
                    }),
                    onLongPress: () => context.push('/oracle'),
                  ),
                ),
                // One primary action (PLAY = shortcut to the Play tab) and ORACLE, whose home is this screen.
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(28, 0, 28, 8),
                    child: Nx2Button(
                      label: context.tx('بازی کن', 'PLAY'),
                      icon: Icons.play_arrow_rounded,
                      kind: Nx2ButtonKind.pink,
                      height: 64,
                      fontSize: 22,
                      onTap: () => nx2GoTab(context, Nx2Tab.games, Nx2Tab.home),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(28, 0, 28, 12),
                    child: Nx2Button(
                      label: context.tx('گفت‌وگو با اوراکل', 'ASK ORACLE'),
                      icon: Icons.auto_awesome_rounded,
                      kind: Nx2ButtonKind.violet,
                      height: 46,
                      fontSize: 14,
                      onTap: () => context.push('/oracle'),
                    ),
                  ),
                ),
                if (p.canClaimDaily)
                  SliverToBoxAdapter(child: _DailyCard(onClaim: _claimDaily)),
                SliverToBoxAdapter(child: _ActivityStrip(profile: p)),
                const SliverToBoxAdapter(child: SizedBox(height: 120)),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

class _Hud extends StatelessWidget {
  const _Hud({required this.profile, required this.coinPoke});
  final ProfileService profile;
  final ValueNotifier<int> coinPoke;

  @override
  Widget build(BuildContext context) {
    final String name =
        profile.username.isEmpty ? context.tx('کاوشگر', 'Explorer') : profile.username;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 10, 0),
      child: Row(children: <Widget>[
        Expanded(
          child: Nx2Pressable(
          onTap: () => context.push('/world/personal_orbit'),
          child: Row(children: <Widget>[
            Nx2AvatarRing(
                size: 62, initial: name.characters.first.toUpperCase()),
            const SizedBox(width: 2),
            Flexible(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            color: Nx2.text)),
                    const SizedBox(height: 2),
                    Text(
                        '${context.tx('سطح', 'LV')} ${profile.level} · ${context.tx(profile.rankTitleFa, profile.rankTitleEn)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 10.5,
                            color: Nx2.muted,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Nx2Progress(value: profile.levelProgress, height: 7),
                  ]),
            ),
          ]),
        ),
        ),
        const SizedBox(width: 4),
        Nx2Stat(
          value: '${profile.coins}',
          wiggle: coinPoke,
          onTap: () => context.push('/world/nexora_exchange'),
        ),
        const SizedBox(width: 6),
        Nx2IconButton(
          icon: Icons.settings_rounded,
          tooltip: context.tx('تنظیمات', 'Settings'),
          onTap: () => context.push('/settings'),
        ),
      ]),
    );
  }
}

class _OracleStage extends StatelessWidget {
  const _OracleStage({
    required this.mood,
    required this.textFa,
    required this.textEn,
    required this.onTap,
    required this.onLongPress,
  });
  final OracleMood mood;
  final String textFa;
  final String textEn;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final double w = MediaQuery.sizeOf(context).width;
    final double stage = (w * 0.62).clamp(200.0, 320.0);
    return SizedBox(
      height: stage + 24,
      child: Stack(alignment: Alignment.bottomCenter, children: <Widget>[
        // crystal dock platform
        Positioned(
          bottom: 0,
          child: Image.asset(Nx2Assets.framesDock,
              width: stage * 0.95,
              cacheWidth: (stage * 2).round(),
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const SizedBox.shrink()),
        ),
        Positioned(
          bottom: stage * 0.24,
          child: OracleMascot(
            mood: mood,
            size: stage * 0.72,
            onTap: onTap,
            onLongPress: onLongPress,
          ),
        ),
        PositionedDirectional(
          top: 6,
          start: 14,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            child: Nx2Bubble(
              key: ValueKey<String>(textEn),
              text: context.tx(textFa, textEn),
              maxWidth: w * 0.5,
            ),
          ),
        ),
      ]),
    );
  }
}

/// Shown only while today's reward is unclaimed (shortcut; its home is Profile › Rewards).
class _DailyCard extends StatelessWidget {
  const _DailyCard({required this.onClaim});
  final VoidCallback onClaim;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      child: Nx2Panel(
        gold: true,
        onTap: onClaim,
        padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
        child: Row(children: <Widget>[
          Image.asset(Nx2Assets.chestsChestLegendary,
              width: 46, height: 46, cacheWidth: 138, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
          const SizedBox(width: 8),
          Expanded(
            child: Text(context.tx('جایزه‌ی امروز آماده است', "Today's reward is ready"),
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5, color: Nx2.gold)),
          ),
          Text(context.tx('بگیر', 'CLAIM'),
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Nx2.text)),
        ]),
      ),
    );
  }
}

class _ActivityStrip extends StatelessWidget {
  const _ActivityStrip({required this.profile});
  final ProfileService profile;

  @override
  Widget build(BuildContext context) {
    final List<ActivityEntry> recent = profile.activity.take(3).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Expanded(
          child: Nx2Panel(
            gold: true,
            onTap: () => context.push('/tournaments'),
            padding: const EdgeInsets.all(10),
            child: Row(children: <Widget>[
              Image.asset(Nx2Assets.badgesTrophyGold,
                  width: 40,
                  height: 48,
                  cacheWidth: 120,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink()),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(context.tx('لیگ و تورنمنت', 'Leagues & Cups'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 12.5,
                              color: Nx2.gold)),
                      Text(context.tx('ثبت‌نام و جایزه', 'Join & win prizes'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, color: Nx2.muted)),
                    ]),
              ),
            ]),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Nx2Panel(
            padding: const EdgeInsets.all(10),
            onTap: () => context.push('/world/personal_orbit?tab=activity'),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(context.tx('آخرین فعالیت', 'Latest activity'),
                      style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 12.5,
                          color: Nx2.cyan)),
                  const SizedBox(height: 2),
                  if (recent.isEmpty)
                    Text(context.tx('هنوز چیزی نیست', 'Nothing yet'),
                        style: const TextStyle(fontSize: 11, color: Nx2.muted))
                  else
                    for (final ActivityEntry a in recent)
                      Text(context.tx(a.textFa, a.textEn),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              const TextStyle(fontSize: 11, color: Nx2.muted)),
                ]),
          ),
        ),
      ]),
    );
  }
}
