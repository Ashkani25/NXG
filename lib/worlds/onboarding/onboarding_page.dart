import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/assets/app_assets.dart';
import '../../games/game_registry.dart';
import '../../core/online/cloud_profile_sync.dart';
import '../../core/profile/profile_service.dart';
import '../../core/settings/app_settings.dart';
import '../../core/theme/nx_theme.dart';
import '../../core/widgets/nx_widgets.dart';

/// Digital identity creation (STEP_08/09, offline guest identity).
/// Online later: the same identity is linked to a Supabase account.
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final _name = TextEditingController();
  String _avatar = 'hero_front';
  int _step = 0;
  final Set<String> _favorites = <String>{};

  static const _avatars = <String, String>{
    'hero_front': AppAssets.charactersOracleEmotesHeroFront,
    'emote_wave': AppAssets.charactersOracleEmotesEmoteWave,
    'emote_smile': AppAssets.charactersOracleEmotesEmoteSmile,
    'emote_cheer': AppAssets.charactersOracleEmotesEmoteCheer,
    'emote_point': AppAssets.charactersOracleEmotesEmotePoint,
    'emote_alert': AppAssets.charactersOracleEmotesEmoteAlert,
  };

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool _nameOk() {
    if (_name.text.trim().length >= 2) return true;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tx('نام کاربری حداقل ۲ حرف باشد',
            'Username must be at least 2 characters'))));
    return false;
  }

  void _toGames() {
    if (!_nameOk()) return;
    FocusScope.of(context).unfocus();
    setState(() => _step = 2);
  }

  Future<void> _finish() async {
    final name = _name.text.trim();
    if (!_nameOk()) {
      setState(() => _step = 1);
      return;
    }
    HapticFeedback.mediumImpact();
    ref.read(settingsProvider).favoriteGames =
        kGames.map((GameInfo g) => g.id).where(_favorites.contains).toList();
    final p = ref.read(profileProvider);
    await p.createIdentity(name: name, avatar: _avatar);
    final outcome = p.award('identity.created', xp: 50, coins: 0);
    ref.read(settingsProvider).markOnboarded();
    if (ref.read(settingsProvider).authMode == 'email') {
      unawaited(ref.read(cloudSyncProvider).identityCreated());
    }
    if (!mounted) return;
    await showAwardOutcome(context, outcome);
    if (mounted) context.go('/hub');
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final p = ref.watch(profileProvider);
    return Scaffold(
      backgroundColor: NxThemeColors.of(context).background,
      body: NxBrandBackground(
        child: SafeArea(
          child: Column(children: [
            _stepBar(),
            Expanded(
              child: AnimatedSwitcher(
                duration: NxMotion.slow,
                child: switch (_step) {
                  0 => _language(s),
                  1 => _identity(p),
                  _ => _games(),
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _language(AppSettings s) {
    final visual = NxThemeColors.of(context);
    return Padding(
      key: const ValueKey('lang'),
      padding: const EdgeInsets.all(NxSpace.md),
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              children: [
                const SizedBox(height: NxSpace.lg),
                const OracleAvatar(pose: 'hero_wave', size: 200),
                const SizedBox(height: NxSpace.lg),
                Text(
                    context.tx('سلام اکتشافگر! من ORACLE هستم.',
                        'Hello Explorer! I am ORACLE.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 25,
                        height: 1.2,
                        fontWeight: FontWeight.w900,
                        color: visual.text)),
                const SizedBox(height: NxSpace.sm),
                Text(
                    context.tx(
                        'زبان خودت را انتخاب کن', 'Choose your language'),
                    style: TextStyle(color: visual.muted)),
                const SizedBox(height: NxSpace.lg),
                Row(children: [
                  Expanded(child: _langButton('fa', 'فارسی', s)),
                  const SizedBox(width: NxSpace.md),
                  Expanded(child: _langButton('en', 'English', s)),
                ]),
                const SizedBox(height: NxSpace.lg),
                Text(context.tx('ظاهر برنامه', 'App look'),
                    style: TextStyle(color: visual.muted)),
                const SizedBox(height: NxSpace.sm),
                SegmentedButton<ThemeMode>(
                  segments: <ButtonSegment<ThemeMode>>[
                    ButtonSegment(value: ThemeMode.dark, icon: const Icon(Icons.dark_mode_rounded),
                        label: Text(context.tx('تیره', 'Dark'))),
                    ButtonSegment(value: ThemeMode.light, icon: const Icon(Icons.light_mode_rounded),
                        label: Text(context.tx('روشن', 'Light'))),
                    ButtonSegment(value: ThemeMode.system, icon: const Icon(Icons.brightness_auto_rounded),
                        label: Text(context.tx('خودکار', 'Auto'))),
                  ],
                  selected: <ThemeMode>{s.themeMode},
                  showSelectedIcon: false,
                  onSelectionChanged: (Set<ThemeMode> v) => s.themeMode = v.first,
                ),
                const SizedBox(height: NxSpace.lg),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => setState(() => _step = 1),
                    child: Text(context.tx('ادامه', 'Continue')),
                  ),
                ),
                const SizedBox(height: NxSpace.md),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _langButton(String code, String label, AppSettings s) {
    final visual = NxThemeColors.of(context);
    final selected = s.languageCode == code;
    return GlassPanel(
      onTap: () => s.languageCode = code,
      borderColor: selected ? visual.accent : null,
      tint: selected ? visual.accent.withValues(alpha: 0.15) : null,
      child: Center(
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (selected) ...[
            Icon(Icons.check_circle_rounded, color: visual.accent, size: 18),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label,
                  maxLines: 1,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: selected ? visual.accent : visual.text)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _identity(ProfileService p) {
    final visual = NxThemeColors.of(context);
    return ListView(
      key: const ValueKey('identity'),
      padding: const EdgeInsets.all(NxSpace.lg),
      children: [
        Text(context.tx('هویت دیجیتال تو', 'Your digital identity'),
            style: TextStyle(
                fontSize: 28,
                height: 1.15,
                fontWeight: FontWeight.w900,
                color: visual.text)),
        const SizedBox(height: 6),
        Text(
          context.tx('این هویت در همه‌ی دنیاهای NEXORA با تو است.',
              'This identity follows you across every NEXORA world.'),
          style: TextStyle(color: visual.muted, height: 1.45),
        ),
        const SizedBox(height: NxSpace.lg),
        GlassPanel(
          child: Row(children: [
            Icon(Icons.badge_rounded, color: visual.accent),
            const SizedBox(width: 10),
            Text('Explorer ID',
                style: TextStyle(color: NxColors.textDim)),
            const Spacer(),
            Flexible(
                child: Text(p.explorerId,
                    textAlign: TextAlign.end,
                    style: TextStyle(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                        color: visual.accent))),
          ]),
        ),
        const SizedBox(height: NxSpace.md),
        TextField(
          controller: _name,
          maxLength: 20,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: context.tx('نام کاربری', 'Username'),
            prefixIcon: const Icon(Icons.alternate_email_rounded),
          ),
        ),
        const SizedBox(height: NxSpace.sm),
        Text(context.tx('ظاهر پایه‌ی آواتار', 'Avatar base look'),
            style: TextStyle(fontWeight: FontWeight.w800, color: visual.text)),
        const SizedBox(height: NxSpace.sm),
        SizedBox(
          height: 130,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final e in _avatars.entries)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 10),
                  child: GestureDetector(
                    onTap: () => setState(() => _avatar = e.key),
                    child: AnimatedContainer(
                      duration: NxMotion.normal,
                      width: 100,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(NxRadius.md),
                        color: _avatar == e.key
                            ? visual.accent.withValues(alpha: 0.18)
                            : visual.surface,
                        border: Border.all(
                            color: _avatar == e.key
                                ? visual.accent
                                : visual.border.withValues(alpha: 0.6),
                            width: _avatar == e.key ? 2 : 1),
                      ),
                      child: Image.asset(e.value,
                          cacheHeight: 300, fit: BoxFit.contain),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: NxSpace.lg),
        GlassPanel(
          child: Row(children: [
            const Icon(Icons.cloud_done_rounded, color: NxColors.turquoise),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.tx(
                    ref.read(settingsProvider).authMode == 'guest'
                        ? 'حالت مهمان فقط آفلاین است؛ پیشرفت و هویت روی همین دستگاه می‌ماند و به سرور وصل نمی‌شود.'
                        : 'ایمیل تو تأیید شده و هویتت به حساب آنلاین NEXORA متصل می‌شود.',
                    ref.read(settingsProvider).authMode == 'guest'
                        ? 'Guest mode is offline-only. Your identity and progress stay on this device and never connect to the server.'
                        : 'Your email is verified and your identity will be connected to your NEXORA account.'),
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ]),
        ),
        const SizedBox(height: NxSpace.lg),
        FilledButton(
          onPressed: _toGames,
          child: Text(context.tx('ادامه', 'Continue')),
        ),
      ],
    );
  }

  /// "Step x of 3" with a back arrow (steps 2 and 3).
  Widget _stepBar() {
    final visual = NxThemeColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 16, 0),
      child: Row(children: [
        SizedBox(
          width: 44,
          child: _step == 0
              ? null
              : IconButton(
                  tooltip: context.tx('قبلی', 'Back'),
                  onPressed: () => setState(() => _step -= 1),
                  icon: const BackButtonIcon()),
        ),
        Expanded(
          child: Row(children: [
            for (int i = 0; i < 3; i++)
              Expanded(
                child: AnimatedContainer(
                  duration: NxMotion.normal,
                  height: 5,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    color: i <= _step ? visual.accent : visual.border.withValues(alpha: 0.4),
                  ),
                ),
              ),
          ]),
        ),
        const SizedBox(width: 10),
        Text(context.tx('${_fa(_step + 1)} از ۳', '${_step + 1} of 3'),
            style: TextStyle(color: visual.muted, fontWeight: FontWeight.w700, fontSize: 12)),
      ]),
    );
  }

  static String _fa(int n) => '۰۱۲۳۴۵۶۷۸۹'[n];

  /// Step 3: favourite games (optional) — they are shown first in the arcade.
  Widget _games() {
    final visual = NxThemeColors.of(context);
    return ListView(
      key: const ValueKey('games'),
      padding: const EdgeInsets.all(NxSpace.lg),
      children: [
        Text(context.tx('چه بازی‌هایی دوست داری؟', 'What do you like to play?'),
            style: TextStyle(fontSize: 26, height: 1.15, fontWeight: FontWeight.w900, color: visual.text)),
        const SizedBox(height: 6),
        Text(
          context.tx('انتخابی است؛ بازی‌های انتخابی اول نشانت داده می‌شوند. بعداً هم همه‌ی بازی‌ها در دسترس‌اند.',
              'Optional: your picks show up first. Every game stays available.'),
          style: TextStyle(color: visual.muted, height: 1.45),
        ),
        const SizedBox(height: NxSpace.lg),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final GameInfo g in kGames)
            FilterChip(
              key: ValueKey('fav_${g.id}'),
              label: Text(context.tx(g.nameFa, g.nameEn)),
              selected: _favorites.contains(g.id),
              selectedColor: g.accent.withValues(alpha: 0.25),
              checkmarkColor: visual.text,
              side: BorderSide(color: _favorites.contains(g.id) ? g.accent : visual.border.withValues(alpha: 0.6)),
              onSelected: (bool on) => setState(() => on ? _favorites.add(g.id) : _favorites.remove(g.id)),
            ),
        ]),
        const SizedBox(height: NxSpace.xl),
        FilledButton.icon(
          onPressed: _finish,
          icon: const Icon(Icons.rocket_launch_rounded),
          label: Text(context.tx('ورود به NEXORA', 'Enter NEXORA')),
        ),
        if (_favorites.isEmpty)
          TextButton(
            onPressed: _finish,
            child: Text(context.tx('رد شدن', 'Skip')),
          ),
      ],
    );
  }
}
