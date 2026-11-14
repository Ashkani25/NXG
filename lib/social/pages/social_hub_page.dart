import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/settings/app_settings.dart';
import '../../online/online_core.dart';
import '../../online/ui/oui.dart';
import '../social_models.dart';
import '../social_ui.dart';

/// /social — entry of the online Social Station.
class SocialHubPage extends StatelessWidget {
  const SocialHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    return OPage(
      title: context.tx('ایستگاه اجتماعی', 'Social Station'),
      en: 'SOCIAL · ONLINE',
      accent: OC.violet,
      body: SocialGate(builder: (BuildContext context, String me) => const _HubBody()),
    );
  }
}

class _HubBody extends StatelessWidget {
  const _HubBody();

  @override
  Widget build(BuildContext context) {
    final OnlineCore core = OnlineCore.instance;
    final SocialProfile? p = core.profile.isEmpty ? null : SocialProfile.fromRow(core.profile);
    return ListView(padding: const EdgeInsets.fromLTRB(14, 6, 14, 24), children: <Widget>[
      OPanel(
        accent: OC.violet,
        glow: true,
        onTap: () => context.push('/social/profile'),
        child: Row(children: <Widget>[
          OAvatar(disc: p?.avatar, url: p?.avatarUrl, size: 62, ring: OC.violet),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: <Widget>[
              Text(p?.displayName ?? '…',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: OC.text, fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              SocialLevelBar(xp: p?.xp ?? 0),
            ]),
          ),
          const Icon(Icons.chevron_right_rounded, color: OC.dim),
        ]),
      ),
      const SizedBox(height: 14),
      _HubTile(
        icon: Icons.people_alt_rounded,
        color: OC.cyan,
        title: context.tx('دوستان', 'Friends'),
        sub: context.tx('جستجو با نام کاربری، درخواست دوستی', 'Search by username, friend requests'),
        route: '/social/friends',
      ),
      _HubTile(
        icon: Icons.forum_rounded,
        color: OC.green,
        title: context.tx('گفتگوها', 'Chats'),
        sub: context.tx('پیام‌های زنده با دوستان و گروه‌ها', 'Live messages with friends and groups'),
        route: '/social/chats',
      ),
      _HubTile(
        icon: Icons.shield_rounded,
        color: OC.gold,
        title: context.tx('باشگاه‌ها', 'Clubs'),
        sub: context.tx('عضو باشگاه شو و با هم‌باشگاهی‌ها گپ بزن', 'Join a club and chat with clubmates'),
        route: '/social/clubs',
      ),
    ]);
  }
}

class _HubTile extends StatelessWidget {
  const _HubTile({required this.icon, required this.color, required this.title, required this.sub, required this.route});
  final IconData icon;
  final Color color;
  final String title;
  final String sub;
  final String route;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: OPanel(
        accent: color,
        pad: 14,
        onTap: () => context.push(route),
        child: Row(children: <Widget>[
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: .16),
              boxShadow: <BoxShadow>[BoxShadow(color: color.withValues(alpha: .3), blurRadius: 14)],
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: <Widget>[
              Text(title, style: const TextStyle(color: OC.text, fontSize: 16, fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text(sub, style: const TextStyle(color: OC.dim, fontSize: 12)),
            ]),
          ),
          const Icon(Icons.chevron_right_rounded, color: OC.dim),
        ]),
      ),
    );
  }
}
