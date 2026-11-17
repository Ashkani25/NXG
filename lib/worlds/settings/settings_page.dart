import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/profile/profile_service.dart';
import '../../core/settings/app_settings.dart';
import '../../core/storage/local_store.dart';
import '../../core/theme/nx_theme.dart';
import '../../core/ui2/nx2_widgets.dart';
import '../../core/widgets/nx_widgets.dart';
import '../../core/online/online_service.dart';
import '../oracle_core/persona/oracle_tour.dart';
import '../../features/admin/admin_access.dart';
import '../../features/tournaments/tournament_watcher.dart';
import 'account_page.dart';

/// The one Settings page (Home › gear), grouped: Account, Notifications, Privacy, Language, Theme,
/// Sound & haptics, Accessibility, ORACLE. Every app-wide preference lives here and nowhere else.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final p = ref.watch(profileProvider);
    final visual = NxThemeColors.of(context);
    final TextStyle note = TextStyle(color: visual.muted, fontSize: 12);
    String qLabel(GraphicsQuality q) => switch (q) {
          GraphicsQuality.low => context.tx('کم', 'Low'),
          GraphicsQuality.medium => context.tx('متوسط', 'Medium'),
          GraphicsQuality.high => context.tx('بالا', 'High'),
          GraphicsQuality.ultra => context.tx('فوق‌العاده', 'Ultra'),
        };
    Widget sw({required String key, required bool value, required ValueChanged<bool>? onChanged,
            required String title, String? subtitle, IconData? icon}) =>
        SwitchListTile(
          key: Key(key),
          contentPadding: EdgeInsets.zero,
          value: value,
          onChanged: onChanged,
          secondary: icon == null ? null : Icon(icon),
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle),
        );
    return NxWorldScaffold(
      title: context.tx('تنظیمات', 'SETTINGS'),
      palette: WorldPalette.hub,
      showWallet: false,
      body: ListView(
        key: const Key('settings.list'),
        padding: const EdgeInsets.all(NxSpace.md),
        children: [
          // ------------------------------------------------------------ Account
          _section(context, context.tx('حساب', 'Account'), Icons.person_rounded),
          GlassPanel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Explorer ID: ${p.explorerId}',
                  style: TextStyle(fontWeight: FontWeight.w700, color: visual.text)),
              const SizedBox(height: 10),
              const AccountStatusCard(),
              const SizedBox(height: 4),
              const _AdminInviteTile(),
              const _OracleAdminTile(),
            ]),
          ),
          // ------------------------------------------------------------ Notifications
          _section(context, context.tx('اعلان‌ها', 'Notifications'), Icons.notifications_rounded),
          GlassPanel(
            child: Column(children: [
              sw(
                  key: 'settings.notify_invites',
                  value: s.notifyInvites,
                  onChanged: (v) => s.notifyInvites = v,
                  icon: Icons.sports_esports_rounded,
                  title: context.tx('دعوت به بازی', 'Game invites'),
                  subtitle: context.tx('وقتی دوستی تو را به بازی آنلاین دعوت می‌کند',
                      'When a friend invites you to an online match')),
              sw(
                  key: 'settings.notify_tournaments',
                  value: s.notifyTournaments,
                  onChanged: (v) {
                    s.notifyTournaments = v;
                    if (!v) TLocalNotifier.cancelAll();
                  },
                  icon: Icons.emoji_events_rounded,
                  title: context.tx('تورنمنت‌ها', 'Tournaments'),
                  subtitle: context.tx('بازی آماده، یادآور ۱۰ دقیقه‌ای، نتیجه و جایزه',
                      'Match ready, 10-minute reminders, results and prizes')),
            ]),
          ),
          // ------------------------------------------------------------ Privacy
          _section(context, context.tx('حریم خصوصی و داده', 'Privacy & data'), Icons.shield_rounded),
          GlassPanel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  context.tx('یک نسخه از داده‌ها همیشه روی همین گوشی می‌ماند (کار آفلاین).',
                      'A copy of your data always stays on this phone (works offline).'),
                  style: note),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                key: const Key('settings.delete_data'),
                style: OutlinedButton.styleFrom(foregroundColor: NxColors.danger),
                icon: const Icon(Icons.delete_forever_rounded),
                label: Text(context.tx('حذف هویت و همه‌ی داده‌ها', 'Delete identity and all data')),
                onPressed: () => _confirmDelete(context, ref),
              ),
            ]),
          ),
          // ------------------------------------------------------------ Language
          _section(context, context.tx('زبان', 'Language'), Icons.translate_rounded),
          GlassPanel(
            child: SegmentedButton<String>(
              key: const Key('settings.language'),
              segments: const [
                ButtonSegment(value: 'fa', label: Text('فارسی')),
                ButtonSegment(value: 'en', label: Text('English')),
              ],
              selected: {s.languageCode},
              onSelectionChanged: (v) => s.languageCode = v.first,
              showSelectedIcon: false,
            ),
          ),
          // ------------------------------------------------------------ Theme
          _section(context, context.tx('پوسته و گرافیک', 'Theme & graphics'), Icons.palette_rounded),
          GlassPanel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SegmentedButton<ThemeMode>(
                key: const Key('settings.theme_mode'),
                segments: [
                  ButtonSegment(
                      value: ThemeMode.system,
                      icon: const Icon(Icons.brightness_auto_rounded),
                      label: Text(context.tx('سیستم', 'System'), key: const Key('settings.theme.system'))),
                  ButtonSegment(
                      value: ThemeMode.dark,
                      icon: const Icon(Icons.dark_mode_rounded),
                      label: Text(context.tx('تیره', 'Dark'), key: const Key('settings.theme.dark'))),
                  ButtonSegment(
                      value: ThemeMode.light,
                      icon: const Icon(Icons.light_mode_rounded),
                      label: Text(context.tx('روشن', 'Light'), key: const Key('settings.theme.light'))),
                ],
                selected: {s.themeMode},
                onSelectionChanged: (v) => s.themeMode = v.first,
                showSelectedIcon: false,
              ),
              const SizedBox(height: 6),
              Text(context.tx('بازی‌ها همیشه تیره می‌مانند.', 'Games always stay dark.'), style: note),
              const SizedBox(height: 14),
              Text(context.tx('کیفیت گرافیک', 'Graphics quality'),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              SegmentedButton<GraphicsQuality>(
                key: const Key('settings.quality'),
                segments: [
                  for (final q in GraphicsQuality.values) ButtonSegment(value: q, label: Text(qLabel(q))),
                ],
                selected: {s.quality},
                onSelectionChanged: (v) => s.quality = v.first,
                showSelectedIcon: false,
              ),
              const SizedBox(height: 6),
              Text(
                  context.tx('کیفیت کمتر = ستاره، ذره و درخشش کمتر و باتری بیشتر.',
                      'Lower quality = fewer stars, particles and glow, better battery.'),
                  style: note),
            ]),
          ),
          // ------------------------------------------------------------ Sound & haptics
          _section(context, context.tx('صدا و لرزش', 'Sound & haptics'), Icons.volume_up_rounded),
          GlassPanel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              sw(
                  key: 'settings.music',
                  value: s.music,
                  onChanged: (v) => s.music = v,
                  icon: Icons.music_note_rounded,
                  title: context.tx('موسیقی منو', 'Menu music'),
                  subtitle: context.tx('در منوها پخش می‌شود و داخل بازی آرام قطع می‌شود',
                      'Plays on menus, fades out inside games')),
              Row(children: [
                Icon(Icons.volume_down_rounded, color: visual.muted),
                Expanded(
                  child: Slider(
                    value: s.musicVolume,
                    onChanged: s.music ? (v) => s.musicVolume = v : null,
                    label: '${(s.musicVolume * 100).round()}%',
                    divisions: 20,
                  ),
                ),
                Icon(Icons.volume_up_rounded, color: visual.muted),
              ]),
              sw(
                  key: 'settings.sound',
                  value: s.sound,
                  onChanged: (v) => s.sound = v,
                  icon: Icons.graphic_eq_rounded,
                  title: context.tx('بازخورد صوتی بازی‌ها', 'Game sound feedback')),
              sw(
                  key: 'settings.haptics',
                  value: s.haptics,
                  onChanged: (v) => s.haptics = v,
                  icon: Icons.vibration_rounded,
                  title: context.tx('لرزش لمسی', 'Haptics')),
            ]),
          ),
          // ------------------------------------------------------------ Accessibility
          _section(context, context.tx('دسترس‌پذیری', 'Accessibility'), Icons.accessibility_new_rounded),
          GlassPanel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.format_size_rounded),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(context.tx('اندازه‌ی متن', 'Text size'),
                        style: const TextStyle(fontWeight: FontWeight.w700))),
                Text('${(s.fontScale * 100).round()}%', key: const Key('settings.font_scale.value')),
              ]),
              Slider(
                key: const Key('settings.font_scale'),
                value: s.fontScale,
                min: AppSettings.minFontScale,
                max: AppSettings.maxFontScale,
                divisions: 9,
                label: '${(s.fontScale * 100).round()}%',
                onChanged: (v) => s.fontScale = v,
              ),
              sw(
                  key: 'settings.high_contrast',
                  value: s.highContrast,
                  onChanged: (v) => s.highContrast = v,
                  icon: Icons.contrast_rounded,
                  title: context.tx('کنتراست بالا', 'High contrast'),
                  subtitle: context.tx('متن و حاشیه‌ی پررنگ‌تر، پس‌زمینه‌ی آرام‌تر',
                      'Stronger text and borders, calmer background')),
              sw(
                  key: 'settings.reduced_motion',
                  value: s.reducedMotion,
                  onChanged: (v) => s.reducedMotion = v,
                  icon: Icons.motion_photos_off_rounded,
                  title: context.tx('کاهش حرکت', 'Reduced motion'),
                  subtitle: context.tx('انیمیشن‌های بلند، حرکت دوربین و درخشش خاموش',
                      'Turns off long animations, camera moves and glow')),
            ]),
          ),
          // ------------------------------------------------------------ ORACLE
          _section(context, 'ORACLE', Icons.auto_awesome_rounded),
          GlassPanel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              sw(
                  key: 'settings.oracle_offline',
                  value: s.oracleOffline,
                  onChanged: (v) => s.oracleOffline = v,
                  icon: Icons.offline_bolt_rounded,
                  title: context.tx('گفتگو فقط روی گوشی', 'Keep chats offline'),
                  subtitle: context.tx('اوراکل فقط روی همین دستگاه جواب می‌دهد و چیزی به سرور فرستاده نمی‌شود',
                      'ORACLE answers on this device only; nothing is sent to the server')),
              sw(
                  key: 'settings.oracle_buddy',
                  value: s.oracleBuddy,
                  onChanged: (v) => s.oracleBuddy = v,
                  icon: Icons.smart_toy_rounded,
                  title: context.tx('اوراکل شیطون گوشه‌ی صفحه', 'Corner ORACLE buddy'),
                  subtitle: context.tx('بکش تا جابه‌جا شود؛ دو بار بزن تا کوچک شود؛ نگه دار تا گفتگو باز شود',
                      'Drag to move; double-tap to minimise; long-press to chat')),
              sw(
                  key: 'settings.oracle_talk',
                  value: s.oracleTalk,
                  onChanged: s.oracleBuddy ? (v) => s.oracleTalk = v : null,
                  icon: Icons.chat_bubble_rounded,
                  title: context.tx('حرف زدن اوراکل', 'ORACLE speech bubbles')),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.tour_rounded, color: visual.accent),
                title: Text(context.tx('دیدن دوباره‌ی تور اوراکل', 'Replay ORACLE tour')),
                subtitle: Text(context.tx('راهنمای قدم‌به‌قدم هر بخش دوباره نشان داده می‌شود',
                    'Every section shows its step-by-step guide again')),
                onTap: () async {
                  final client = ref.read(onlineProvider).client;
                  await OracleTourStore.reset(client?.auth.currentUser?.id, client: client);
                  OracleTourStore.replayTick.value++;
                },
              ),
            ]),
          ),
          const SizedBox(height: NxSpace.xl),
          Center(
            child: Text('NEXORA · YOUR UNIVERSE. YOUR IDENTITY. YOUR EXPERIENCE.',
                textAlign: TextAlign.center,
                style: TextStyle(color: visual.muted.withValues(alpha: 0.7), fontSize: 10)),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final p = ref.read(profileProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tx('مطمئنی؟', 'Are you sure?')),
        content: Text(ctx.tx('همه‌ی پیشرفت، آیتم‌ها و پست‌ها پاک می‌شوند. قابل بازگشت نیست.',
            'All progress, items and posts will be erased. This cannot be undone.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tx('انصراف', 'Cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: NxColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.tx('حذف', 'Delete')),
          ),
        ],
      ),
    );
    if (ok == true) {
      final store = LocalStore.instance;
      for (final k in store.prefs.getKeys().toList()) {
        if (!k.startsWith('settings.')) await store.remove(k);
      }
      await p.resetAll();
      if (context.mounted) context.go('/onboarding');
    }
  }

  Widget _section(BuildContext context, String t, IconData icon) {
    final Color c = NxThemeColors.of(context).accent;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, NxSpace.lg, 4, NxSpace.sm),
      child: Row(children: [
        Icon(icon, size: 18, color: c),
        const SizedBox(width: 8),
        Text(t, style: TextStyle(fontWeight: FontWeight.w900, color: c, letterSpacing: 0.5)),
      ]),
    );
  }
}


/// Any signed-in user can redeem the one-time code issued by the main admin.
/// The server, not this widget, decides whether the code and account are valid.
class _AdminInviteTile extends ConsumerWidget {
  const _AdminInviteTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.vpn_key_rounded, color: NxThemeColors.of(context).accent),
        title: Text(context.tx('ورود کد دعوت ادمین', 'Redeem admin invitation code')),
        subtitle: Text(context.tx('کد را از مدیر اصلی بگیر', 'Use a code issued by the main admin')),
        onTap: () async {
          final TextEditingController code = TextEditingController();
          final String? value = await showDialog<String>(
            context: context,
            builder: (BuildContext ctx) => AlertDialog(
              title: Text(ctx.tx('کد دعوت ادمین', 'Admin invitation code')),
              content: TextField(
                controller: code,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(hintText: 'NX-XXXXXXXX'),
              ),
              actions: <Widget>[
                TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tx('انصراف', 'Cancel'))),
                FilledButton(onPressed: () => Navigator.pop(ctx, code.text), child: Text(ctx.tx('ثبت', 'Redeem'))),
              ],
            ),
          );
          code.dispose();
          if (value == null || value.trim().isEmpty || !context.mounted) return;
          final Map<String, dynamic> result = await AdminApi(ref.read(onlineProvider)).redeemAdminCode(value);
          if (!context.mounted) return;
          final bool fa = context.isFa;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(result['ok'] == true
                ? (fa ? 'دسترسی ساخت تورنمنت فعال شد ✓' : 'Tournament-admin access enabled ✓')
                : adminErrorText(result['error'] as String?, fa)),
          ));
          if (result['ok'] == true) await ref.read(adminAccessProvider).refresh();
        },
      );
}

/// Admin entries: the admin panel for any admin, the ORACLE form for the 'oracle' permission (server re-checks).
class _OracleAdminTile extends ConsumerWidget {
  const _OracleAdminTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AdminAccess a = ref.watch(adminAccessProvider);
    if (!a.isAdmin) return const SizedBox.shrink();
    return Column(children: <Widget>[
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.admin_panel_settings_rounded, color: Nx2.ink(Nx2.goldBright)),
        title: Text(a.owner ? context.tx('پنل مدیر اصلی', 'Main admin panel') : context.tx('پنل مدیریت', 'Admin panel')),
        onTap: () => context.push('/admin'),
      ),
      if (a.can(AdminPerm.oracle))
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.psychology_alt_rounded, color: Nx2.ink(Nx2.goldBright)),
          title: Text(context.tx('تنظیمات شخصیت اوراکل (مدیر)', 'ORACLE personality config (admin)')),
          onTap: () => context.push('/admin/oracle'),
        ),
    ]);
  }
}
