import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/settings/app_settings.dart';
import '../../online/ui/oui.dart';
import '../social_models.dart';
import '../social_repository.dart';
import '../social_ui.dart';

/// /social/friends — friends list, incoming/outgoing requests, search by username.
class SocialFriendsPage extends StatelessWidget {
  const SocialFriendsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return OPage(
      title: context.tx('دوستان', 'Friends'),
      en: 'FRIENDS',
      accent: OC.cyan,
      body: SocialGate(builder: (BuildContext context, String me) => _FriendsBody(key: ValueKey<String>(me), me: me)),
    );
  }
}

class _FriendsBody extends StatefulWidget {
  const _FriendsBody({super.key, required this.me});
  final String me;

  @override
  State<_FriendsBody> createState() => _FriendsBodyState();
}

class _FriendsBodyState extends State<_FriendsBody> {
  final SocialRepository repo = SocialRepository.instance;
  final TextEditingController _q = TextEditingController();
  Timer? _debounce;
  FriendsSnapshot? _snap;
  List<SocialProfile> _results = <SocialProfile>[];
  bool _loading = true;
  bool _searching = false;
  String _error = '';
  final Set<String> _busy = <String>{};

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
    setState(() {
      _loading = _snap == null;
      _error = '';
    });
    final SocialResult<FriendsSnapshot> r = await repo.friends();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.ok) {
        _snap = r.value;
      } else {
        _error = r.error;
      }
    });
  }

  void _onQuery(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(v));
  }

  Future<void> _search(String v) async {
    final String q = v.trim();
    if (q.length < 2) {
      setState(() {
        _results = <SocialProfile>[];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    final SocialResult<List<SocialProfile>> r = await repo.searchUsers(q);
    if (!mounted || _q.text.trim() != q) return;
    setState(() {
      _searching = false;
      _results = r.value ?? <SocialProfile>[];
    });
    if (!r.ok) socialToast(context, false, r.error);
  }

  Future<void> _run(String id, Future<bool> Function() f) async {
    setState(() => _busy.add(id));
    final bool ok = await f();
    if (!mounted) return;
    setState(() => _busy.remove(id));
    if (ok) await _load();
  }

  Future<bool> _send(String id) async {
    final SocialResult<String> r = await repo.sendFriendRequest(id);
    if (!mounted) return r.ok;
    socialToast(context, r.ok, r.error,
        r.value == 'friends' ? context.tx('حالا با هم دوستید', 'You are now friends') : context.tx('درخواست دوستی ارسال شد', 'Friend request sent'));
    return r.ok;
  }

  Future<bool> _bool(Future<SocialResult<bool>> f, String okMsg) async {
    final SocialResult<bool> r = await f;
    if (mounted) socialToast(context, r.ok, r.error, okMsg);
    return r.ok;
  }

  Future<void> _message(String id) async {
    setState(() => _busy.add(id));
    final SocialResult<String> r = await repo.openDm(id);
    if (!mounted) return;
    setState(() => _busy.remove(id));
    if (r.ok && r.value != null) {
      context.push('/social/chats/${r.value}');
    } else {
      socialToast(context, false, r.error);
    }
  }

  List<Widget> _actionsFor(SocialProfile u, FriendState st) {
    final bool busy = _busy.contains(u.id);
    switch (st) {
      case FriendState.self:
        return <Widget>[];
      case FriendState.friends:
        return <Widget>[
          SocialIconBtn(icon: Icons.chat_bubble_rounded, tooltip: context.tx('پیام', 'Message'), color: OC.violet, busy: busy, onTap: () => _message(u.id)),
        ];
      case FriendState.incoming:
        return <Widget>[
          SocialIconBtn(
              icon: Icons.check_rounded,
              tooltip: context.tx('پذیرفتن', 'Accept'),
              color: OC.green,
              busy: busy,
              onTap: () => _run(u.id, () => _bool(repo.respondFriendRequest(u.id, true), context.tx('حالا با هم دوستید', 'You are now friends')))),
          SocialIconBtn(
              icon: Icons.close_rounded,
              tooltip: context.tx('رد کردن', 'Decline'),
              color: OC.red,
              busy: busy,
              onTap: () => _run(u.id, () => _bool(repo.respondFriendRequest(u.id, false), context.tx('رد شد', 'Declined')))),
        ];
      case FriendState.outgoing:
        return <Widget>[
          SocialIconBtn(
              icon: Icons.undo_rounded,
              tooltip: context.tx('لغو درخواست', 'Cancel request'),
              color: OC.orange,
              busy: busy,
              onTap: () => _run(u.id, () => _bool(repo.cancelFriendRequest(u.id), context.tx('لغو شد', 'Cancelled')))),
        ];
      case FriendState.none:
        return <Widget>[
          SocialIconBtn(
              icon: Icons.person_add_alt_1_rounded,
              tooltip: context.tx('افزودن دوست', 'Add friend'),
              busy: busy,
              onTap: () => _run(u.id, () => _send(u.id))),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final FriendsSnapshot? s = _snap;
    final String me = widget.me;
    final bool searchMode = _q.text.trim().length >= 2;
    return Column(children: <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
        child: TextField(
          controller: _q,
          onChanged: _onQuery,
          style: const TextStyle(color: OC.text),
          decoration: InputDecoration(
            hintText: context.tx('جستجوی نام کاربری…', 'Search username…'),
            hintStyle: const TextStyle(color: OC.dim),
            prefixIcon: const Icon(Icons.search_rounded, color: OC.cyan),
            suffixIcon: _q.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear_rounded, color: OC.dim),
                    onPressed: () {
                      _q.clear();
                      _search('');
                    },
                  ),
            filled: true,
            fillColor: const Color(0x22080C22),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: OC.line)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: OC.cyan)),
          ),
        ),
      ),
      Expanded(child: searchMode ? _searchList(s, me) : _mainList(s, me)),
    ]);
  }

  Widget _searchList(FriendsSnapshot? s, String me) {
    if (_searching) return oSpinner();
    if (_results.isEmpty) {
      return OEmpty(icon: Icons.person_search_rounded, title: context.tx('کاربری پیدا نشد', 'No users found'));
    }
    return ListView(padding: const EdgeInsets.fromLTRB(14, 0, 14, 24), children: <Widget>[
      for (final SocialProfile u in _results)
        SocialUserRow(user: u, trailing: _actionsFor(u, s?.stateOf(me, u.id) ?? FriendState.none)),
    ]);
  }

  Widget _mainList(FriendsSnapshot? s, String me) {
    if (_loading) return Padding(padding: const EdgeInsets.all(14), child: oSkeleton());
    if (s == null) return Center(child: OError(_error.isEmpty ? context.tx('خطا', 'Error') : _error, onRetry: _load));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(14, 0, 14, 24), children: <Widget>[
        if (s.incoming.isNotEmpty) ...<Widget>[
          oCap('${context.tx('درخواست‌های دریافتی', 'Incoming requests')} · ${context.fn(s.incoming.length)}'),
          for (final SocialProfile u in s.incoming) SocialUserRow(user: u, trailing: _actionsFor(u, FriendState.incoming)),
        ],
        oCap('${context.tx('دوستان', 'Friends')} · ${context.fn(s.friends.length)}'),
        if (s.friends.isEmpty)
          OEmpty(
            icon: Icons.group_add_rounded,
            title: context.tx('هنوز دوستی نداری', 'No friends yet'),
            sub: context.tx('نام کاربری را بالا جستجو کن و درخواست بفرست', 'Search a username above and send a request'),
          )
        else
          for (final SocialProfile u in s.friends) SocialUserRow(user: u, trailing: _actionsFor(u, FriendState.friends)),
        if (s.outgoing.isNotEmpty) ...<Widget>[
          oCap('${context.tx('درخواست‌های ارسالی', 'Sent requests')} · ${context.fn(s.outgoing.length)}'),
          for (final SocialProfile u in s.outgoing) SocialUserRow(user: u, trailing: _actionsFor(u, FriendState.outgoing)),
        ],
      ]),
    );
  }
}
