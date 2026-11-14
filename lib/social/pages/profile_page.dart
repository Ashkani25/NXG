import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/settings/app_settings.dart';
import '../../online/online_core.dart';
import '../../online/ui/oui.dart';
import '../social_models.dart';
import '../social_repository.dart';
import '../social_ui.dart';

/// /social/profile — the signed-in user's online profile (profiles row), editable.
class SocialMyProfilePage extends StatelessWidget {
  const SocialMyProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return OPage(
      title: context.tx('پروفایل من', 'My profile'),
      en: 'PROFILE',
      accent: OC.violet,
      body: SocialGate(builder: (BuildContext context, String me) => _MyProfileBody(key: ValueKey<String>(me))),
    );
  }
}

class _MyProfileBody extends StatefulWidget {
  const _MyProfileBody({super.key});

  @override
  State<_MyProfileBody> createState() => _MyProfileBodyState();
}

class _MyProfileBodyState extends State<_MyProfileBody> {
  final SocialRepository repo = SocialRepository.instance;
  final TextEditingController _name = TextEditingController();
  final TextEditingController _bio = TextEditingController();
  final TextEditingController _avatar = TextEditingController();
  SocialProfile? _p;
  bool _loading = true;
  bool _saving = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    _avatar.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    final SocialResult<SocialProfile?> r = await repo.myProfile();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (!r.ok) {
        _error = r.error;
        return;
      }
      _p = r.value;
      _fill();
    });
  }

  void _fill() {
    final SocialProfile? p = _p;
    if (p == null) return;
    _name.text = p.username;
    _bio.text = p.bio ?? '';
    _avatar.text = p.avatarUrl ?? '';
  }

  Future<void> _save() async {
    final SocialProfile? p = _p;
    if (p == null) return;
    final String name = _name.text.trim();
    final String? bad = validateUsername(name);
    if (bad != null) {
      otoast(context, bad, err: true);
      return;
    }
    final String url = _avatar.text.trim();
    if (url.isNotEmpty && !url.startsWith('https://')) {
      otoast(context, context.tx('آدرس تصویر باید با https:// شروع شود', 'Avatar URL must start with https://'), err: true);
      return;
    }
    setState(() => _saving = true);
    final SocialResult<SocialProfile?> r = await repo.updateMyProfile(
      username: name == p.username ? null : name,
      bio: _bio.text.trim() == (p.bio ?? '') ? null : _bio.text,
      avatarUrl: url == (p.avatarUrl ?? '') ? null : url,
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (r.ok && r.value != null) _p = r.value;
    });
    socialToast(context, r.ok, r.error, context.tx('ذخیره شد', 'Saved'));
  }

  InputDecoration _dec(String label, IconData icon) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: OC.dim),
        prefixIcon: Icon(icon, color: OC.violet),
        filled: true,
        fillColor: const Color(0x22080C22),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: OC.line)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: OC.violet)),
      );

  @override
  Widget build(BuildContext context) {
    if (_loading) return oSpinner();
    if (_error.isNotEmpty) return Center(child: OError(_error, onRetry: _load));
    final SocialProfile? p = _p;
    if (p == null) {
      return Center(child: OError(context.tx('پروفایل پیدا نشد', 'Profile not found'), onRetry: _load));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(14, 6, 14, 28), children: <Widget>[
        _ProfileHeader(p: p),
        oSection(context.tx('ویرایش', 'Edit')),
        TextField(
          controller: _name,
          maxLength: 20,
          style: const TextStyle(color: OC.text),
          decoration: _dec(context.tx('نام کاربری (نام نمایشی)', 'Username (display name)'), Icons.alternate_email_rounded),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _bio,
          maxLength: 160,
          maxLines: 3,
          minLines: 1,
          style: const TextStyle(color: OC.text),
          decoration: _dec(context.tx('درباره من', 'Bio'), Icons.notes_rounded),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _avatar,
          keyboardType: TextInputType.url,
          textDirection: TextDirection.ltr,
          style: const TextStyle(color: OC.text),
          decoration: _dec(context.tx('آدرس تصویر آواتار (https)', 'Avatar image URL (https)'), Icons.image_rounded),
        ),
        const SizedBox(height: 14),
        OBtn(context.tx('ذخیره پروفایل', 'Save profile'), style: OBtnStyle.violet, busy: _saving, onTap: _save),
        const SizedBox(height: 10),
        OBtn(context.tx('حساب و ورود', 'Account & sign-in'), style: OBtnStyle.dark, small: true, onTap: () => context.push(kSocialLoginRoute)),
      ]),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.p});
  final SocialProfile p;

  @override
  Widget build(BuildContext context) {
    return OPanel(
      accent: OC.violet,
      glow: true,
      pad: 16,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        Center(child: OAvatar(disc: p.avatar, url: p.avatarUrl, size: 88, ring: OC.violet, dot: p.isOnlineAt(DateTime.now()) ? OC.green : null)),
        const SizedBox(height: 10),
        Text(p.displayName, textAlign: TextAlign.center, style: const TextStyle(color: OC.text, fontSize: 21, fontWeight: FontWeight.w900)),
        if ((p.bio ?? '').isNotEmpty) ...<Widget>[
          const SizedBox(height: 4),
          Text(p.bio!, textAlign: TextAlign.center, style: const TextStyle(color: OC.dim, fontSize: 13)),
        ],
        const SizedBox(height: 12),
        SocialLevelBar(xp: p.xp),
        const SizedBox(height: 12),
        Row(children: <Widget>[
          _Stat(label: context.tx('برد', 'Wins'), value: context.fn(p.wins), color: OC.green),
          _Stat(label: context.tx('باخت', 'Losses'), value: context.fn(p.losses), color: OC.red),
          _Stat(label: context.tx('مساوی', 'Draws'), value: context.fn(p.draws), color: OC.sky),
          _Stat(label: context.tx('امتیاز', 'Rating'), value: context.fn(p.rating), color: OC.gold),
        ]),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(children: <Widget>[
          Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w900)),
          Text(label, style: const TextStyle(color: OC.dim, fontSize: 11)),
        ]),
      );
}

/// /social/user/:id — another user's public profile with friend + message actions.
class SocialUserProfilePage extends StatelessWidget {
  const SocialUserProfilePage({super.key, required this.userId});
  final String userId;

  @override
  Widget build(BuildContext context) {
    return OPage(
      title: context.tx('پروفایل', 'Profile'),
      en: 'PILOT',
      accent: OC.cyan,
      body: SocialGate(builder: (BuildContext context, String me) => _UserBody(userId: userId, me: me)),
    );
  }
}

class _UserBody extends StatefulWidget {
  const _UserBody({required this.userId, required this.me});
  final String userId;
  final String me;

  @override
  State<_UserBody> createState() => _UserBodyState();
}

class _UserBodyState extends State<_UserBody> {
  final SocialRepository repo = SocialRepository.instance;
  SocialProfile? _p;
  FriendState _state = FriendState.none;
  bool _loading = true;
  bool _busy = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    final SocialResult<SocialProfile?> r = await repo.profile(widget.userId);
    final SocialResult<FriendsSnapshot> f = await repo.friends();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (!r.ok) {
        _error = r.error;
        return;
      }
      _p = r.value;
      final FriendsSnapshot? s = f.value;
      _state = s == null ? (widget.userId == widget.me ? FriendState.self : FriendState.none) : s.stateOf(widget.me, widget.userId);
    });
  }

  Future<void> _act(Future<bool> Function() f) async {
    setState(() => _busy = true);
    final bool ok = await f();
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) await _load();
  }

  Future<bool> _add() async {
    final SocialResult<String> r = await repo.sendFriendRequest(widget.userId);
    if (!mounted) return r.ok;
    socialToast(context, r.ok, r.error,
        r.value == 'friends' ? context.tx('حالا با هم دوستید', 'You are now friends') : context.tx('درخواست دوستی ارسال شد', 'Friend request sent'));
    return r.ok;
  }

  Future<bool> _simple(Future<SocialResult<bool>> f, String okMsg) async {
    final SocialResult<bool> r = await f;
    if (mounted) socialToast(context, r.ok, r.error, okMsg);
    return r.ok;
  }

  Future<void> _message() async {
    setState(() => _busy = true);
    final SocialResult<String> r = await repo.openDm(widget.userId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok && r.value != null) {
      context.push('/social/chats/${r.value}');
    } else {
      socialToast(context, false, r.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return oSpinner();
    if (_error.isNotEmpty) return Center(child: OError(_error, onRetry: _load));
    final SocialProfile? p = _p;
    if (p == null) return Center(child: OEmpty(icon: Icons.person_off_rounded, title: context.tx('کاربر پیدا نشد', 'User not found')));
    final List<Widget> actions = <Widget>[];
    switch (_state) {
      case FriendState.self:
        actions.add(OBtn(context.tx('ویرایش پروفایل من', 'Edit my profile'), onTap: () => context.push('/social/profile')));
        break;
      case FriendState.none:
        actions.add(OBtn(context.tx('افزودن دوست', 'Add friend'), busy: _busy, onTap: () => _act(_add)));
        break;
      case FriendState.outgoing:
        actions.add(OBtn(context.tx('لغو درخواست', 'Cancel request'),
            style: OBtnStyle.dark,
            busy: _busy,
            onTap: () => _act(() => _simple(repo.cancelFriendRequest(widget.userId), context.tx('لغو شد', 'Cancelled')))));
        break;
      case FriendState.incoming:
        actions.add(OBtn(context.tx('پذیرفتن درخواست دوستی', 'Accept friend request'),
            style: OBtnStyle.green,
            busy: _busy,
            onTap: () => _act(() => _simple(repo.respondFriendRequest(widget.userId, true), context.tx('حالا با هم دوستید', 'You are now friends')))));
        break;
      case FriendState.friends:
        actions.add(OBtn(context.tx('حذف از دوستان', 'Remove friend'),
            style: OBtnStyle.red,
            small: true,
            busy: _busy,
            onTap: () => _act(() => _simple(repo.removeFriend(widget.userId), context.tx('حذف شد', 'Removed')))));
        break;
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(14, 6, 14, 28), children: <Widget>[
        _ProfileHeader(p: p),
        const SizedBox(height: 14),
        if (_state != FriendState.self) ...<Widget>[
          OBtn(context.tx('پیام', 'Message'), style: OBtnStyle.violet, busy: _busy, onTap: _message),
          const SizedBox(height: 10),
        ],
        ...actions,
      ]),
    );
  }
}
