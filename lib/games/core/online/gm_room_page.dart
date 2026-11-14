/// Waiting room of an online arcade game: seats, ready, host start, chat — and the live match
/// once the room is playing (reconnects straight into a running match).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:nexora/core/settings/app_settings.dart';
import 'package:nexora/core/theme/nx_theme.dart';
import 'package:nexora/core/widgets/nx_widgets.dart';
import 'package:nexora/online/link.dart';
import 'package:nexora/online/models.dart';
import 'package:nexora/online/online_core.dart';
import 'package:nexora/online/supabase_client.dart';

import 'gm_backend.dart';
import 'gm_match_screen.dart';
import 'gm_models.dart';
import 'gm_widgets.dart';

/// seat index used by the server: slot * 2 + team
int gmSeatOfPlayer(RoomPlayer p) => (p.slot ?? 0) * 2 + (p.team ?? 0);

class GmRoomPage extends StatefulWidget {
  const GmRoomPage({super.key, required this.gameId, required this.roomId, this.backend});
  final String gameId;
  final String roomId;
  final GmBackend? backend;

  @override
  State<GmRoomPage> createState() => _GmRoomPageState();
}

class _GmRoomPageState extends State<GmRoomPage> {
  GmBackend get _b => widget.backend ?? const SupabaseGmBackend();
  RoomLink? _link;
  String? _active;
  String _dismissed = '';
  bool _busy = false;
  String? _error;
  final TextEditingController _chat = TextEditingController();

  @override
  void initState() {
    super.initState();
    _attach();
  }

  Future<void> _attach() async {
    await OnlineCore.instance.boot();
    if (!mounted) return;
    RoomLink? l = OnlineCore.instance.linkForRoom(widget.roomId);
    if (l == null) {
      OnlineCore.instance.enterRoom(<String, dynamic>{'id': widget.roomId});
      l = OnlineCore.instance.link;
    }
    if (l == null) {
      setState(() => _error = context.tx('اول وارد حساب آنلاین شو', 'Sign in to your online account first'));
      return;
    }
    l.addListener(_onLink);
    setState(() => _link = l);
    _onLink();
  }

  void _onLink() {
    final RoomLink? l = _link;
    if (l == null || !mounted) return;
    final Room? r = l.state.room;
    final String? cm = r?.currentMatch;
    if (r != null && r.playing && cm != null && cm.isNotEmpty && cm != _dismissed && _active != cm) {
      _active = cm;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _link?.removeListener(_onLink);
    _chat.dispose();
    super.dispose();
  }

  String _err(Object e) => gmErrorText(errMessage(e), context.isFa);

  Future<void> _run(Future<void> Function() f) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await f();
      _link?.ping();
      await _link?.refresh();
    } catch (e) {
      if (mounted) _error = _err(e);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _leave() async {
    await OnlineCore.instance.leaveRoom();
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final String? active = _active;
    if (active != null) {
      return GmMatchPage(
        gameId: widget.gameId,
        matchId: active,
        onBack: () => setState(() {
          _dismissed = active;
          _active = null;
          _link?.refresh();
        }),
      );
    }
    final GmGameSpec? spec = gmSpec(widget.gameId);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop) _leave();
      },
      child: NxWorldScaffold(
        title: spec == null ? widget.gameId : context.tx(spec.nameFa, spec.nameEn),
        palette: WorldPalette.arcade,
        showWallet: false,
        actions: <Widget>[
          IconButton(
            tooltip: context.tx('خروج از اتاق', 'Leave room'),
            onPressed: _leave,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
        body: _body(context, spec),
      ),
    );
  }

  Widget _body(BuildContext context, GmGameSpec? spec) {
    final RoomLink? l = _link;
    if (l == null) {
      return Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!));
    }
    final LinkState st = l.state;
    if (!st.loaded) return const Center(child: CircularProgressIndicator());
    final Room? room = st.room;
    if (st.gone || room == null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Text(context.tx('دیگر در این اتاق نیستی', 'You are no longer in this room')),
          const SizedBox(height: 12),
          FilledButton(onPressed: () => Navigator.of(context).maybePop(), child: Text(context.tx('بازگشت', 'Back'))),
        ]),
      );
    }
    final String me = l.me;
    final bool host = room.host == me;
    final int cap = gmInt(room.settings['seats'], 2);
    final List<RoomPlayer> seated = st.players.where((RoomPlayer p) => p.isPlayer).toList();
    final RoomPlayer? mine = st.player(me);
    final bool iSit = mine != null && mine.isPlayer;
    final bool quick = room.settings['quick'] == true;
    final int minSeats = spec?.minSeats ?? 2;
    final bool allReady = seated.every((RoomPlayer p) => p.ready || p.userId == room.host);
    return ListView(padding: const EdgeInsets.all(NxSpace.md), children: <Widget>[
      GlassPanel(
        child: Row(children: <Widget>[
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text(room.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              Text(
                '${context.tx('کد', 'Code')}: ${room.code}  •  ${room.ranked ? context.tx('رتبه‌ای', 'ranked') : context.tx('دوستانه', 'friendly')}',
                style: const TextStyle(color: NxColors.textDim),
              ),
            ]),
          ),
          IconButton(
            tooltip: context.tx('کپی کد', 'Copy code'),
            onPressed: () => Clipboard.setData(ClipboardData(text: room.code)),
            icon: const Icon(Icons.copy_rounded),
          ),
        ]),
      ),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: NxColors.danger))),
      const SizedBox(height: 12),
      Text(context.tx('صندلی‌ها', 'Seats'), style: const TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
        for (int s = 0; s < cap; s++) _seat(context, st, room, s, me),
      ]),
      const SizedBox(height: 8),
      if (st.players.any((RoomPlayer p) => !p.isPlayer))
        Text(
          context.tx('تماشاگرها: ', 'Spectators: ') +
              st.players.where((RoomPlayer p) => !p.isPlayer).map((RoomPlayer p) => p.name).join(context.isFa ? '، ' : ', '),
          style: const TextStyle(color: NxColors.textDim, fontSize: 12),
        ),
      const SizedBox(height: 12),
      if (host && !quick && spec != null && spec.maxSeats > spec.minSeats)
        Wrap(spacing: 6, children: <Widget>[
          for (final int n in spec.seatChoices)
            ChoiceChip(
              label: Text(context.tx('${gmNum(context, n)} نفره', '$n players')),
              selected: cap == n,
              onSelected: _busy ? null : (bool _) => _run(() => _b.updateRoom(room.id, seats: n)),
            ),
        ]),
      const SizedBox(height: 8),
      if (quick)
        Text(
          context.tx('بازی سریع: وقتی همه‌ی صندلی‌ها پر شد خودکار شروع می‌شود…', 'Quick match: starts by itself once every seat is taken…'),
          style: const TextStyle(color: NxColors.gold),
        )
      else if (host)
        FilledButton.icon(
          onPressed: _busy || !iSit || seated.length < minSeats || !allReady ? null : () => _run(() => _b.start(room.id)),
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(seated.length < minSeats
              ? context.tx('حداقل ${gmNum(context, minSeats)} بازیکن لازم است', 'Needs at least $minSeats players')
              : (allReady ? context.tx('شروع بازی', 'Start match') : context.tx('منتظر آماده شدن همه…', 'Waiting for everyone to be ready…'))),
        )
      else if (iSit)
        FilledButton.icon(
          onPressed: _busy ? null : () => _run(() => _b.setReady(room.id, !(mine.ready))),
          icon: Icon(mine.ready ? Icons.check_circle_rounded : Icons.radio_button_unchecked),
          label: Text(mine.ready ? context.tx('آماده‌ام ✓', 'Ready ✓') : context.tx('اعلام آمادگی', 'I am ready')),
        ),
      if (room.playing && room.currentMatch != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: OutlinedButton.icon(
            onPressed: () => setState(() => _active = room.currentMatch),
            icon: const Icon(Icons.visibility_rounded),
            label: Text(context.tx('بازی در جریان است — ورود', 'Match running — open it')),
          ),
        ),
      const SizedBox(height: 16),
      _chatBox(context, l),
    ]);
  }

  Widget _seat(BuildContext context, LinkState st, Room room, int s, String me) {
    RoomPlayer? p;
    for (final RoomPlayer x in st.players) {
      if (x.isPlayer && gmSeatOfPlayer(x) == s) p = x;
    }
    final Color col = gmSeatColor(s);
    final bool online = p != null && st.online.containsKey(p.userId);
    return SizedBox(
      width: 150,
      child: GlassPanel(
        padding: const EdgeInsets.all(10),
        borderColor: p == null ? Colors.white24 : col,
        onTap: p == null && !room.playing ? () => _run(() => _b.takeSeat(room.id, s)) : null,
        child: Row(children: <Widget>[
          CircleAvatar(radius: 12, backgroundColor: p == null ? Colors.white12 : col, child: Text(gmNum(context, s + 1), style: const TextStyle(fontSize: 11, color: Colors.black))),
          const SizedBox(width: 8),
          Expanded(
            child: p == null
                ? Text(context.tx('خالی — بنشین', 'Empty — sit'), style: const TextStyle(color: NxColors.textDim, fontSize: 12))
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                    Text(p.name + (p.userId == me ? context.tx(' (تو)', ' (you)') : ''),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    Row(children: <Widget>[
                      Icon(Icons.circle, size: 8, color: online ? NxColors.success : Colors.white24),
                      const SizedBox(width: 4),
                      if (p.userId == room.host) const Icon(Icons.star_rounded, size: 14, color: NxColors.gold),
                      if (p.ready) const Icon(Icons.check_rounded, size: 14, color: NxColors.success),
                    ]),
                  ]),
          ),
        ]),
      ),
    );
  }

  Widget _chatBox(BuildContext context, RoomLink l) {
    final List<ChatMsg> msgs = l.state.chat;
    final List<ChatMsg> shown = msgs.length > 30 ? msgs.sublist(msgs.length - 30) : msgs;
    return GlassPanel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        Text(context.tx('گفتگو', 'Chat'), style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        for (final ChatMsg m in shown)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text.rich(TextSpan(children: <InlineSpan>[
              TextSpan(text: '${m.name}: ', style: const TextStyle(fontWeight: FontWeight.w700, color: NxColors.turquoise)),
              TextSpan(text: m.text),
            ])),
          ),
        Row(children: <Widget>[
          Expanded(
            child: TextField(
              controller: _chat,
              maxLength: 200,
              decoration: InputDecoration(hintText: context.tx('پیام…', 'Message…'), counterText: '', isDense: true),
              onSubmitted: (String t) {
                l.sendChat(t);
                _chat.clear();
              },
            ),
          ),
          IconButton(
            onPressed: () {
              l.sendChat(_chat.text);
              _chat.clear();
            },
            icon: const Icon(Icons.send_rounded),
          ),
        ]),
      ]),
    );
  }
}
