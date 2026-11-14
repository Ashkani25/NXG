import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/settings/app_settings.dart';
import '../../online/ui/oui.dart';
import '../social_models.dart';
import '../social_repository.dart';
import '../social_ui.dart';

String _policyLabel(BuildContext context, ClubInfo c) {
  switch (c.joinPolicy) {
    case 'open':
      return context.tx('آزاد', 'Open');
    case 'invite':
      return context.tx('فقط دعوت', 'Invite only');
    default:
      return context.tx('با درخواست', 'By request');
  }
}

class _ClubEmblem extends StatelessWidget {
  const _ClubEmblem({required this.club});
  final ClubInfo club;
  static const double size = 48;

  @override
  Widget build(BuildContext context) {
    final String e = club.emblem;
    final bool isUrl = e.startsWith('http');
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: OC.gold.withValues(alpha: .14),
        border: Border.all(color: OC.gold.withValues(alpha: .7)),
        boxShadow: <BoxShadow>[BoxShadow(color: OC.gold.withValues(alpha: .25), blurRadius: 12)],
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: isUrl
          ? Image.network(e, fit: BoxFit.cover, cacheWidth: (size * 3).round(), errorBuilder: (_, __, ___) => const Icon(Icons.shield_rounded, color: OC.gold))
          : (e.isNotEmpty && e.runes.length <= 2
              ? Text(e, style: TextStyle(fontSize: size * .5))
              : Text(club.tag.isEmpty ? '?' : club.tag,
                  style: TextStyle(color: OC.gold, fontWeight: FontWeight.w900, fontSize: size * (club.tag.length > 3 ? .24 : .3)))),
    );
  }
}

/// /social/clubs — list of clubs (club_list view), my club on top, join / leave.
class SocialClubsPage extends StatelessWidget {
  const SocialClubsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return OPage(
      title: context.tx('باشگاه‌ها', 'Clubs'),
      en: 'CLUBS',
      accent: OC.gold,
      body: SocialGate(builder: (BuildContext context, String me) => _ClubsBody(key: ValueKey<String>(me))),
    );
  }
}

class _ClubsBody extends StatefulWidget {
  const _ClubsBody({super.key});

  @override
  State<_ClubsBody> createState() => _ClubsBodyState();
}

class _ClubsBodyState extends State<_ClubsBody> {
  final SocialRepository repo = SocialRepository.instance;
  final TextEditingController _q = TextEditingController();
  Timer? _debounce;
  List<ClubInfo>? _clubs;
  ClubMembership? _mine;
  ClubInfo? _myClub;
  String _error = '';
  String _busy = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final SocialResult<ClubMembership?> m = await repo.myClub();
    final SocialResult<List<ClubInfo>> r = await repo.clubs(query: _q.text);
    ClubInfo? my;
    final ClubMembership? mem = m.value;
    if (mem != null) {
      final List<ClubInfo> list = r.value ?? <ClubInfo>[];
      for (final ClubInfo c in list) {
        if (c.id == mem.clubId) my = c;
      }
      if (my == null) {
        final SocialResult<List<ClubInfo>> all = await repo.clubs();
        for (final ClubInfo c in all.value ?? <ClubInfo>[]) {
          if (c.id == mem.clubId) my = c;
        }
      }
    }
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _clubs = r.value;
        _error = '';
      } else {
        _error = r.error;
      }
      _mine = mem;
      _myClub = my;
    });
  }

  Future<void> _join(ClubInfo c) async {
    setState(() => _busy = c.id);
    final SocialResult<String> r = await repo.joinClub(c.id);
    if (!mounted) return;
    setState(() => _busy = '');
    socialToast(context, r.ok, r.error,
        r.value == 'requested' ? context.tx('درخواست عضویت ارسال شد', 'Join request sent') : context.tx('به باشگاه پیوستی!', 'You joined the club!'));
    if (r.ok) await _load();
  }

  Future<void> _leave() async {
    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: const Color(0xF50A0F2C),
        title: Text(ctx.tx('ترک باشگاه؟', 'Leave club?'), style: const TextStyle(color: OC.text)),
        content: Text(ctx.tx('مطمئنی می‌خواهی از باشگاه خارج شوی؟', 'Are you sure you want to leave the club?'),
            style: const TextStyle(color: OC.dim)),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(ctx.tx('نه', 'No'))),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(ctx.tx('ترک', 'Leave'), style: const TextStyle(color: OC.red))),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _busy = 'leave');
    final SocialResult<bool> r = await repo.leaveClub();
    if (!mounted) return;
    setState(() => _busy = '');
    socialToast(context, r.ok, r.error, context.tx('از باشگاه خارج شدی', 'You left the club'));
    if (r.ok) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final List<ClubInfo>? clubs = _clubs;
    if (clubs == null) {
      if (_error.isNotEmpty) return Center(child: OError(_error, onRetry: _load));
      return Padding(padding: const EdgeInsets.all(14), child: oSkeleton());
    }
    final ClubInfo? my = _myClub;
    final bool inClub = _mine != null;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(14, 4, 14, 24), children: <Widget>[
        if (my != null) ...<Widget>[
          oCap(context.tx('باشگاه من', 'My club')),
          OPanel(
            accent: OC.gold,
            glow: true,
            onTap: () => context.push('/social/clubs/${my.id}'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
              _ClubRowContent(club: my),
              const SizedBox(height: 10),
              Row(children: <Widget>[
                if (my.conversationId != null)
                  Expanded(
                    child: OBtn(context.tx('گپ باشگاه', 'Club chat'),
                        small: true, style: OBtnStyle.gold, onTap: () => context.push('/social/chats/${my.conversationId}')),
                  ),
                if (my.conversationId != null) const SizedBox(width: 8),
                Expanded(
                  child: OBtn(context.tx('ترک باشگاه', 'Leave club'), small: true, style: OBtnStyle.dark, busy: _busy == 'leave', onTap: _leave),
                ),
              ]),
            ]),
          ),
        ],
        const SizedBox(height: 8),
        TextField(
          controller: _q,
          onChanged: (String _) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 400), _load);
          },
          style: const TextStyle(color: OC.text),
          decoration: InputDecoration(
            hintText: context.tx('جستجوی نام یا تگ باشگاه…', 'Search club name or tag…'),
            hintStyle: const TextStyle(color: OC.dim),
            prefixIcon: const Icon(Icons.search_rounded, color: OC.gold),
            filled: true,
            fillColor: const Color(0x22080C22),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: OC.line)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: OC.gold)),
          ),
        ),
        oCap('${context.tx('همه‌ی باشگاه‌ها', 'All clubs')} · ${context.fn(clubs.length)}'),
        if (clubs.isEmpty) OEmpty(icon: Icons.shield_outlined, title: context.tx('باشگاهی پیدا نشد', 'No clubs found')),
        for (final ClubInfo c in clubs)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: OPanel(
              pad: 10,
              onTap: () => context.push('/social/clubs/${c.id}'),
              child: Row(children: <Widget>[
                Expanded(child: _ClubRowContent(club: c)),
                if (!inClub && !c.inviteOnly && !c.full)
                  SocialIconBtn(
                    icon: c.open ? Icons.login_rounded : Icons.mark_email_unread_rounded,
                    tooltip: c.open ? context.tx('پیوستن', 'Join') : context.tx('درخواست عضویت', 'Request to join'),
                    color: OC.gold,
                    busy: _busy == c.id,
                    onTap: () => _join(c),
                  ),
              ]),
            ),
          ),
      ]),
    );
  }
}

class _ClubRowContent extends StatelessWidget {
  const _ClubRowContent({required this.club});
  final ClubInfo club;

  @override
  Widget build(BuildContext context) {
    final String cap = club.maxMembers > 0 ? '${context.fn(club.members)}/${context.fn(club.maxMembers)}' : context.fn(club.members);
    return Row(children: <Widget>[
      _ClubEmblem(club: club),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: <Widget>[
          Row(children: <Widget>[
            Flexible(
              child: Text(club.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: OC.text, fontWeight: FontWeight.w900, fontSize: 14)),
            ),
            const SizedBox(width: 6),
            if (club.tag.isNotEmpty) OBadge(club.tag, color: OC.gold),
          ]),
          const SizedBox(height: 3),
          Text(
            '👥 $cap · ⚡ ${context.fn(club.power)} · ${_policyLabel(context, club)}'
            '${club.minLevel > 1 ? ' · ${context.tx('سطح', 'Lv')} ${context.fn(club.minLevel)}+' : ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: OC.dim, fontSize: 11),
          ),
        ]),
      ),
    ]);
  }
}

/// /social/clubs/:id — club detail: description, members, join/leave, club chat.
class SocialClubDetailPage extends StatelessWidget {
  const SocialClubDetailPage({super.key, required this.clubId});
  final String clubId;

  @override
  Widget build(BuildContext context) {
    return OPage(
      title: context.tx('باشگاه', 'Club'),
      en: 'CLUB',
      accent: OC.gold,
      body: SocialGate(builder: (BuildContext context, String me) => _ClubDetailBody(clubId: clubId, me: me)),
    );
  }
}

class _ClubDetailBody extends StatefulWidget {
  const _ClubDetailBody({required this.clubId, required this.me});
  final String clubId;
  final String me;

  @override
  State<_ClubDetailBody> createState() => _ClubDetailBodyState();
}

class _ClubDetailBodyState extends State<_ClubDetailBody> {
  final SocialRepository repo = SocialRepository.instance;
  ClubInfo? _club;
  List<SocialProfile> _members = <SocialProfile>[];
  ClubMembership? _mine;
  bool _loading = true;
  bool _busy = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final SocialResult<List<ClubInfo>> all = await repo.clubs();
    final SocialResult<List<SocialProfile>> mem = await repo.clubMembers(widget.clubId);
    final SocialResult<ClubMembership?> mine = await repo.myClub();
    if (!mounted) return;
    ClubInfo? club;
    for (final ClubInfo c in all.value ?? <ClubInfo>[]) {
      if (c.id == widget.clubId) club = c;
    }
    setState(() {
      _loading = false;
      _error = all.ok ? '' : all.error;
      _club = club;
      _members = mem.value ?? <SocialProfile>[];
      _mine = mine.value;
    });
  }

  Future<void> _join() async {
    setState(() => _busy = true);
    final SocialResult<String> r = await repo.joinClub(widget.clubId);
    if (!mounted) return;
    setState(() => _busy = false);
    socialToast(context, r.ok, r.error,
        r.value == 'requested' ? context.tx('درخواست عضویت ارسال شد', 'Join request sent') : context.tx('به باشگاه پیوستی!', 'You joined the club!'));
    if (r.ok) await _load();
  }

  Future<void> _leave() async {
    setState(() => _busy = true);
    final SocialResult<bool> r = await repo.leaveClub();
    if (!mounted) return;
    setState(() => _busy = false);
    socialToast(context, r.ok, r.error, context.tx('از باشگاه خارج شدی', 'You left the club'));
    if (r.ok) await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return oSpinner();
    final ClubInfo? c = _club;
    if (c == null) {
      if (_error.isNotEmpty) return Center(child: OError(_error, onRetry: _load));
      return Center(child: OEmpty(icon: Icons.shield_outlined, title: context.tx('باشگاه پیدا نشد', 'Club not found')));
    }
    final ClubMembership? mine = _mine;
    final bool member = mine != null && mine.clubId == c.id;
    final bool inOther = mine != null && !member;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(14, 4, 14, 24), children: <Widget>[
        OPanel(
          accent: OC.gold,
          glow: true,
          pad: 14,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
            _ClubRowContent(club: c),
            if ((c.description ?? '').isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Text(c.description!, style: const TextStyle(color: OC.text, fontSize: 13)),
            ],
            const SizedBox(height: 12),
            if (member) ...<Widget>[
              OBadge(_roleLabel(context, mine.role), color: OC.gold),
              const SizedBox(height: 10),
              if (c.conversationId != null) ...<Widget>[
                OBtn(context.tx('گپ باشگاه', 'Club chat'), style: OBtnStyle.gold, onTap: () => context.push('/social/chats/${c.conversationId}')),
                const SizedBox(height: 8),
              ],
              OBtn(context.tx('ترک باشگاه', 'Leave club'), style: OBtnStyle.dark, small: true, busy: _busy, onTap: _leave),
            ] else if (inOther)
              Text(context.tx('برای پیوستن، اول باشگاه فعلی‌ات را ترک کن', 'Leave your current club first to join this one'),
                  textAlign: TextAlign.center, style: const TextStyle(color: OC.dim, fontSize: 12))
            else if (c.inviteOnly)
              Text(context.tx('این باشگاه فقط با دعوت عضو می‌گیرد', 'This club is invite only'),
                  textAlign: TextAlign.center, style: const TextStyle(color: OC.dim, fontSize: 12))
            else if (c.full)
              Text(context.tx('ظرفیت باشگاه پر است', 'This club is full'), textAlign: TextAlign.center, style: const TextStyle(color: OC.dim, fontSize: 12))
            else
              OBtn(c.open ? context.tx('پیوستن به باشگاه', 'Join club') : context.tx('درخواست عضویت', 'Request to join'),
                  style: OBtnStyle.gold, busy: _busy, onTap: _join),
          ]),
        ),
        oCap('${context.tx('اعضا', 'Members')} · ${context.fn(_members.length)}'),
        for (final SocialProfile p in _members) SocialUserRow(user: p),
      ]),
    );
  }

  String _roleLabel(BuildContext context, String role) {
    switch (role) {
      case 'leader':
      case 'owner':
        return context.tx('رهبر', 'Leader');
      case 'officer':
        return context.tx('افسر', 'Officer');
      default:
        return context.tx('عضو', 'Member');
    }
  }
}
