/// Shared widgets of the online Social Station, built on the online look (lib/online/ui/oui.dart).
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/settings/app_settings.dart';
import '../online/online_core.dart';
import '../online/supabase_client.dart';
import '../online/ui/oui.dart';
import 'social_models.dart';

/// Route of the existing online login / account screen.
const String kSocialLoginRoute = '/online/account';

/// Boots the online layer and shows [builder] only when signed in; otherwise an honest
/// "no connection" or "sign in" state that routes to the online account page.
class SocialGate extends StatefulWidget {
  const SocialGate({super.key, required this.builder});
  final Widget Function(BuildContext context, String me) builder;

  @override
  State<SocialGate> createState() => _SocialGateState();
}

class _SocialGateState extends State<SocialGate> {
  final OnlineCore core = OnlineCore.instance;
  bool _booting = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    if (Online.ready) return;
    setState(() => _booting = true);
    await core.boot();
    if (mounted) setState(() => _booting = false);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: core,
      builder: (BuildContext context, Widget? _) {
        if (_booting) return oSpinner();
        if (!Online.ready) {
          return Center(child: OError(context.tx('اتصال به سرور برقرار نیست', 'Cannot reach the server'), onRetry: _boot));
        }
        if (!core.signedIn) {
          return Center(
            child: OEmpty(
              icon: Icons.lock_person_rounded,
              title: context.tx('برای ورود به ایستگاه اجتماعی وارد حساب شو', 'Sign in to enter the Social Station'),
              sub: context.tx('دوستان، گفتگوها و باشگاه‌ها به حساب آنلاین نیاز دارند', 'Friends, chats and clubs need an online account'),
              action: context.tx('ورود / ساخت حساب', 'Sign in / create account'),
              onAction: () => context.push(kSocialLoginRoute),
            ),
          );
        }
        return widget.builder(context, core.uid);
      },
    );
  }
}

/// Row showing a user (avatar, name, level, online dot) with trailing actions.
class SocialUserRow extends StatelessWidget {
  const SocialUserRow({super.key, required this.user, this.trailing = const <Widget>[], this.onTap, this.subtitle});
  final SocialProfile user;
  final List<Widget> trailing;
  final VoidCallback? onTap;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final bool online = user.isOnlineAt(DateTime.now());
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: OPanel(
        pad: 10,
        onTap: onTap ?? () => context.push('/social/user/${user.id}'),
        child: Row(children: <Widget>[
          OAvatar(disc: user.avatar, url: user.avatarUrl, size: 44, dot: online ? OC.green : null),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: <Widget>[
              Text(user.displayName,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: OC.text, fontWeight: FontWeight.w800, fontSize: 14)),
              const SizedBox(height: 2),
              Text(subtitle ?? '${context.tx('سطح', 'Level')} ${context.fn(user.level)}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: OC.dim, fontSize: 11)),
            ]),
          ),
          ...trailing,
        ]),
      ),
    );
  }
}

/// Small round icon action.
class SocialIconBtn extends StatelessWidget {
  const SocialIconBtn({super.key, required this.icon, required this.tooltip, this.onTap, this.color = OC.cyan, this.busy = false});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final Color color;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 6),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: color.withValues(alpha: .14),
          shape: CircleBorder(side: BorderSide(color: color.withValues(alpha: .5))),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: busy ? null : onTap,
            child: SizedBox(
              width: 38,
              height: 38,
              child: Center(
                child: busy
                    ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: color))
                    : Icon(icon, size: 19, color: color),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Level badge with progress bar.
class SocialLevelBar extends StatelessWidget {
  const SocialLevelBar({super.key, required this.xp});
  final int xp;

  @override
  Widget build(BuildContext context) {
    final int lvl = socialLevelForXp(xp);
    final int next = socialXpForLevel(lvl + 1);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: <Widget>[
      Row(children: <Widget>[
        OBadge('${context.tx('سطح', 'Lv')} ${context.fn(lvl)}', color: OC.gold),
        const Spacer(),
        Text('${context.fn(xp)} / ${context.fn(next)} XP', style: const TextStyle(color: OC.dim, fontSize: 11)),
      ]),
      const SizedBox(height: 6),
      OBar(socialLevelProgress(xp), color: OC.gold),
    ]);
  }
}

/// Toast for a failed / successful result.
void socialToast(BuildContext context, bool ok, String error, [String okMsg = '']) {
  if (!context.mounted) return;
  if (ok) {
    if (okMsg.isNotEmpty) otoast(context, okMsg);
  } else {
    otoast(context, error, err: true);
  }
}
