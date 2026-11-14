/// Room lobby (port of the Godot app's src/online/lobby.gd = RN Lobby.tsx + OnlineRoot navigation):
/// seats per team, spectators, ready / start, host settings (mode / rule / turn / field / name via
/// update_room) + kick, chat, voice, share code, auto 3-2-1 start for quick/arena rooms, a host
/// returning to a stuck "playing" room ends that match. Uses OnlineCore.link (RoomLink).
/// RPC: take_seat, set_ready, start_match, kick, spectate, update_room, abandon_match, leave_room.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/settings/app_settings.dart';
import '../link.dart';
import '../models.dart';
import '../online_core.dart';
import '../ui/oui.dart';
import '../ui/room_widgets.dart';
import 'hub_page.dart' show FieldPicker;

class OnlineLobbyPage extends StatefulWidget {
  const OnlineLobbyPage({super.key, required this.roomId, this.skipMatch = '', this.why = ''});
  final String roomId;
  final String skipMatch;
  final String why;

  @override
  State<OnlineLobbyPage> createState() => _OnlineLobbyPageState();
}

class _OnlineLobbyPageState extends State<OnlineLobbyPage> {
  final OnlineCore core = OnlineCore.instance;
  RoomLink? link;
  String busy = '';
  int count = 0;
  Timer? _countT;
  bool _left = false;

  @override
  void initState() {
    super.initState();
    link = core.linkForRoom(widget.roomId);
    final RoomLink? l = link;
    if (l == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/online');
      });
      return;
    }
    if (widget.skipMatch.isNotEmpty) {
      core.skipMatch = widget.skipMatch;
      core.firstLoad = false;
      l.refresh();
    }
    l.addListener(_onChange);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onChange());
  }

  @override
  void dispose() {
    link?.removeListener(_onChange);
    _countT?.cancel();
    super.dispose();
  }

  String get me => link?.me ?? '';
  LinkState get st => link?.state ?? const LinkState();
  Room? get room => st.room;

  // ---------------------------------------------------------------- state → navigation (OnlineRoot)
  void _onChange() {
    final RoomLink? l = link;
    if (l == null || !mounted || _left) return;
    if (!st.loaded) return setState(() {});
    final Room? r = room;
    if (st.gone) {
      _left = true;
      otoast(context, r != null ? context.ot('lobby.you_left_the_room') : context.ot('lobby.the_room_was_closed'), err: true);
      core.dropLink();
      context.go('/online');
      return;
    }
    if (r == null) return;
    if (core.firstLoad) {
      core.firstLoad = false;
      // a host coming back to a room stuck in "playing" (e.g. app was killed) ends that match
      final String cm0 = r.currentMatch ?? '';
      if (r.status == 'playing' && cm0.isNotEmpty && r.host == me) {
        core.skipMatch = cm0;
        callRpc('abandon_match', <String, dynamic>{'p_match': cm0}).then((OnlineResult x) {
          if (x.ok && !l.disposed) l.ping();
        });
        return setState(() {});
      }
    }
    final String cm = r.currentMatch ?? '';
    if (r.status == 'playing' && cm.isNotEmpty && cm != core.skipMatch) {
      _goMatch(cm);
      return;
    }
    _autoStart();
    setState(() {});
  }

  void _goMatch(String mid) {
    final RoomLink? l = link;
    if (l == null || _left) return;
    _left = true;
    core.beforeProfile = Map<String, dynamic>.from(core.profile);
    core.skipMatch = mid;
    _countStop();
    context.pushReplacement('/online/match/${l.id}/$mid');
  }

  List<List<RoomPlayer?>> _seats() {
    final int n = teamSizeOf(room?.mode ?? '1v1');
    final List<List<RoomPlayer?>> t = <List<RoomPlayer?>>[List<RoomPlayer?>.filled(n, null), List<RoomPlayer?>.filled(n, null)];
    for (final RoomPlayer p in st.players) {
      final int? tm = p.team, sl = p.slot;
      if (p.isPlayer && tm != null && sl != null && (tm == 0 || tm == 1) && sl >= 0 && sl < n) t[tm][sl] = p;
    }
    return t;
  }

  bool get _full => _seats().every((List<RoomPlayer?> t) => t.every((RoomPlayer? x) => x != null));
  List<RoomPlayer> get _notReady => st.players.where((RoomPlayer p) => p.isPlayer && !p.ready && p.userId != room?.host).toList();

  // ---------------------------------------------------------------- auto start 3-2-1 (quick / arena)
  void _autoStart() {
    final Room? r = room;
    if (r == null) return;
    final bool auto = (r.kind == 'quick' || r.kind == 'arena') && r.status == 'waiting' && _full && _notReady.isEmpty;
    if (auto && _countT == null) {
      count = 3;
      buzz('light');
      _countT = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => count--);
        buzz('light');
        if (count <= 0) {
          _countStop();
          if (room?.host == me) _start();
        }
      });
    } else if (!auto && _countT != null) {
      _countStop();
    }
  }

  void _countStop() {
    _countT?.cancel();
    _countT = null;
    count = 0;
  }

  // ---------------------------------------------------------------- actions
  Future<void> _run(String key, String fn, Map<String, dynamic> args, {String okMsg = ''}) async {
    if (busy.isNotEmpty) return;
    setState(() => busy = key);
    final OnlineResult r = await callRpc(fn, args);
    if (!mounted) return;
    if (r.ok) {
      link?.ping();
      await link?.refresh();
      if (mounted && okMsg.isNotEmpty) otoast(context, okMsg);
    } else {
      otoast(context, r.error, err: true);
      buzz('heavy');
    }
    if (mounted) setState(() => busy = '');
  }

  String get _rid => room?.id ?? widget.roomId;

  void _sit(int team, int slot) => _run('seat$team$slot', 'take_seat', <String, dynamic>{'p_room': _rid, 'p_team': team, 'p_slot': slot});
  void _readyToggle() {
    final bool cur = st.player(me)?.ready ?? false;
    buzz('medium');
    _run('ready', 'set_ready', <String, dynamic>{'p_room': _rid, 'p_ready': !cur});
  }

  void _start() {
    buzz('heavy');
    _run('start', 'start_match', <String, dynamic>{'p_room': _rid});
  }

  void _kick(String u) => _run('kick$u', 'kick', <String, dynamic>{'p_room': _rid, 'p_user': u}, okMsg: context.ot('lobby.player_kicked'));
  void _watch() => _run('spec', 'spectate', <String, dynamic>{'p_room': _rid});

  void _copy() {
    Clipboard.setData(ClipboardData(text: room?.code ?? ''));
    otoast(context, context.ot('lobby.room_code_copied'));
    buzz('light');
  }

  void _share() {
    final String t = context.ot('lobby.let_s_play_nexora_nroom').replaceAll(r'\n', '\n');
    Clipboard.setData(ClipboardData(text: fmtArgs(t, <Object>[room?.code ?? ''])));
    otoast(context, context.ot('lobby.invite_text_copied_send_it'));
  }

  Future<void> _askLeave() async {
    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        backgroundColor: const Color(0xF50A0F2C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: const BorderSide(color: OC.red)),
        title: Text(context.ot('lobby.leave_the_room'), textAlign: TextAlign.center, style: const TextStyle(color: OC.text)),
        content: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Text(context.ot('lobby.your_slot_will_be_freed'), textAlign: TextAlign.center, style: const TextStyle(color: OC.dim, fontSize: 12)),
          const SizedBox(height: 14),
          OBtn(context.ot('nav.stay'), onTap: () => Navigator.of(c).pop(false)),
          const SizedBox(height: 8),
          OBtn(context.ot('nav.quit'), small: true, style: OBtnStyle.red, onTap: () => Navigator.of(c).pop(true)),
        ]),
      ),
    );
    if (yes != true || !mounted) return;
    _left = true;
    link?.voiceLeave();
    await core.leaveRoom();
    if (mounted) context.go('/online');
  }

  void _openChat() {
    final RoomLink? l = link;
    if (l == null) return;
    showOSheet<void>(context, title: context.ot('lobby.chat'), en: 'ROOM CHAT', builder: (_) => OChatPanel(l));
  }

  void _openSettings() {
    final Room? r = room;
    if (r == null) return;
    showOSheet<void>(
      context,
      title: context.ot('lobby.room_settings'),
      en: 'ROOM SETTINGS',
      builder: (BuildContext sc) => _RoomSettingsSheet(room: r, link: link!, onDone: () => Navigator.of(sc).pop()),
    );
  }

  // ---------------------------------------------------------------- UI
  @override
  Widget build(BuildContext context) {
    final RoomLink? l = link;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool did, Object? _) {
        if (!did) _askLeave();
      },
      child: OPage(
        title: room?.name ?? '…',
        en: 'LOBBY',
        onBack: _askLeave,
        actions: <Widget>[
          IconButton(icon: const Icon(Icons.share_rounded, color: OC.cyan, size: 20), onPressed: _share),
          if (l != null) Padding(padding: const EdgeInsetsDirectional.only(end: 8), child: OPingBadge(l)),
        ],
        body: Stack(children: <Widget>[
          if (l == null || !st.loaded || room == null) oSpinner(36) else _body(context, l),
          if (count > 0)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: const Color(0xB302040E),
                  alignment: Alignment.center,
                  child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                    TweenAnimationBuilder<double>(
                      key: ValueKey<int>(count),
                      tween: Tween<double>(begin: 1.5, end: 1),
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeOutBack,
                      builder: (BuildContext context, double s, Widget? c) => Transform.scale(scale: s, child: c),
                      child: Text(context.fn(count),
                          style: const TextStyle(color: Colors.white, fontSize: 96, fontWeight: FontWeight.w900, shadows: <Shadow>[Shadow(color: OC.cyan, blurRadius: 24)])),
                    ),
                    Text(context.ot('lobby.the_match_is_starting'), style: const TextStyle(color: OC.cyan, fontSize: 16, fontWeight: FontWeight.w800)),
                  ]),
                ),
              ),
            ),
        ]),
        bottom: (l == null || room == null) ? null : _actionBar(context),
      ),
    );
  }

  Widget _body(BuildContext context, RoomLink l) {
    final Room r = room!;
    final bool isHost = r.host == me;
    final bool playing = r.status == 'playing';
    final int n = teamSizeOf(r.mode);
    final List<List<RoomPlayer?>> seats = _seats();
    final List<RoomPlayer> specs = st.players.where((RoomPlayer p) => p.role == 'spectator').toList();
    final bool amPlayer = st.player(me)?.isPlayer ?? false;
    final Map<String, dynamic> settings = r.settings;
    return ListenableBuilder(
      listenable: l.voice,
      builder: (BuildContext context, _) {
        final List<String> speaking = l.voice.state.speaking;
        return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: <Widget>[
          OPanel(
            accent: OC.cyan,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
              Row(children: <Widget>[
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                    Text(context.ot('lobby.room_code'), style: const TextStyle(color: OC.dim, fontSize: 11)),
                    Text(r.code, textDirection: TextDirection.ltr, style: const TextStyle(color: OC.cyan, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 3)),
                  ]),
                ),
                TextButton(onPressed: _copy, child: Text(context.ot('lobby.copy'))),
                TextButton(onPressed: _share, child: Text(context.ot('lobby.share'))),
              ]),
              const SizedBox(height: 6),
              Wrap(spacing: 4, runSpacing: 4, children: <Widget>[
                OBadge(ruleLabel(context, settings), color: OC.violet),
                OBadge(r.ranked ? context.ot('hub.ranked') : context.ot('lobby.friendly'), color: r.ranked ? OC.gold : OC.green),
                OBadge(modeLabel(context, r.mode), color: OC.sky),
                if ((r.tournamentMatchId ?? '').isNotEmpty) OBadge(context.ot('hub.tournament'), color: OC.orange),
                if (playing) OBadge(context.ot('lobby.in_game'), color: OC.red, live: true),
              ]),
            ]),
          ),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            for (int t = 0; t < 2; t++) ...<Widget>[
              Expanded(child: _team(context, t, n, seats[t], isHost, playing, speaking)),
              if (t == 0) const SizedBox(width: 8),
            ],
          ]),
          if (specs.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            OPanel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Row(children: <Widget>[
                  Expanded(
                    child: Text(context.otf('lobby.spectators_x', <Object>[context.fn(specs.length)]),
                        style: const TextStyle(color: OC.text, fontWeight: FontWeight.w800, fontSize: 12)),
                  ),
                ]),
                const SizedBox(height: 6),
                SizedBox(
                  height: 64,
                  child: ListView(scrollDirection: Axis.horizontal, children: <Widget>[
                    for (final RoomPlayer p in specs)
                      SizedBox(
                        width: 64,
                        child: Column(children: <Widget>[
                          OAvatar(
                            disc: _discOf(p),
                            url: p.profile?.avatarUrl,
                            size: 40,
                            ring: speaking.contains(p.userId) ? OC.green : OC.dim2,
                            dim: !st.online.containsKey(p.userId),
                          ),
                          Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: OC.dim, fontSize: 10)),
                        ]),
                      ),
                  ]),
                ),
              ]),
            ),
          ],
          if (amPlayer && !playing) ...<Widget>[
            const SizedBox(height: 6),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                onPressed: busy.isEmpty ? _watch : null,
                icon: const Icon(Icons.visibility_rounded, size: 16, color: OC.sky),
                label: Text(context.ot('lobby.spectate_only'), style: const TextStyle(color: OC.sky, fontSize: 12)),
              ),
            ),
          ],
          const SizedBox(height: 10),
          OPanel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text(context.ot('hub.voice_chat'), style: const TextStyle(color: OC.text, fontWeight: FontWeight.w800, fontSize: 12)),
              const SizedBox(height: 8),
              OVoiceBar(l, enabled: r.voice),
            ]),
          ),
          const SizedBox(height: 10),
          OPanel(
            onTap: _openChat,
            child: Row(children: <Widget>[
              const Icon(Icons.forum_rounded, color: OC.cyan, size: 30),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Text(context.ot('lobby.room_chat'), style: const TextStyle(color: OC.text, fontWeight: FontWeight.w800, fontSize: 12)),
                  Text(
                    st.chat.isNotEmpty ? '${st.chat.last.name}: ${st.chat.last.text}' : context.ot('lobby.tap_to_type_a_message'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: OC.dim, fontSize: 11),
                  ),
                ]),
              ),
              if (st.unread > 0)
                CircleAvatar(radius: 11, backgroundColor: OC.red, child: Text(context.fn(st.unread > 9 ? 9 : st.unread), style: const TextStyle(color: Colors.white, fontSize: 11))),
            ]),
          ),
          if (isHost && !playing && (r.tournamentMatchId ?? '').isEmpty && (r.kind == 'casual' || r.kind == 'social')) ...<Widget>[
            const SizedBox(height: 10),
            OBtn(context.ot('lobby.room_settings'), small: true, style: OBtnStyle.dark, onTap: _openSettings),
          ],
        ]);
      },
    );
  }

  static String _discOf(RoomPlayer p) {
    final String e = p.profile?.equippedDisc ?? '';
    return e.isNotEmpty ? e : (p.profile?.avatar ?? '');
  }

  Widget _team(BuildContext context, int t, int n, List<RoomPlayer?> seats, bool isHost, bool playing, List<String> speaking) {
    final Color col = t == 0 ? OC.cyan : OC.red;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      Container(
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: col.withValues(alpha: .18), borderRadius: BorderRadius.circular(12), border: Border.all(color: col.withValues(alpha: .4))),
        child: Text(t == 0 ? context.ot('lobby.blue_team') : context.ot('lobby.red_team'), style: TextStyle(color: col, fontWeight: FontWeight.w900)),
      ),
      for (int k = 0; k < n; k++) ...<Widget>[
        const SizedBox(height: 8),
        if (seats[k] != null) _seat(context, seats[k]!, col, isHost && seats[k]!.userId != me && !playing, speaking) else _empty(context, t, k, playing),
      ],
    ]);
  }

  Widget _empty(BuildContext context, int t, int k, bool playing) {
    final bool b = busy == 'seat$t$k';
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: playing || busy.isNotEmpty ? null : () => _sit(t, k),
      child: Container(
        height: 68,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: const Color(0x66060A1E), borderRadius: BorderRadius.circular(16), border: Border.all(color: OC.dim2)),
        child: b
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: OC.cyan))
            : Row(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
                const Text('+', style: TextStyle(color: OC.dim, fontSize: 18, fontWeight: FontWeight.w900)),
                const SizedBox(width: 4),
                Text(context.ot('lobby.sit'), style: const TextStyle(color: OC.dim, fontSize: 11)),
              ]),
      ),
    );
  }

  Widget _seat(BuildContext context, RoomPlayer p, Color color, bool canKick, List<String> speaking) {
    final String uid = p.userId;
    final bool isH = uid == room?.host;
    final bool talking = speaking.contains(uid);
    final bool online = st.online.containsKey(uid);
    final ({double power, double accuracy}) ds = discStatsOf((p.discId ?? '').isNotEmpty ? p.discId! : (p.profile?.equippedDisc ?? ''));
    return Container(
      constraints: const BoxConstraints(minHeight: 68),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xE00A102C),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: talking ? OC.green : (uid == me ? color : OC.line)),
      ),
      child: Row(children: <Widget>[
        OAvatar(disc: _discOf(p), url: p.profile?.avatarUrl, size: 40, ring: talking ? OC.green : color, dim: !online, dot: online ? OC.green : OC.dim2),
        const SizedBox(width: 6),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text('${isH ? '👑 ' : ''}${p.name}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: OC.text, fontSize: 12, fontWeight: FontWeight.w800)),
            Text(isH ? context.ot('lobby.host') : (p.ready ? context.ot('lobby.ready') : context.ot('lobby.not_ready')),
                style: TextStyle(color: isH ? OC.gold : (p.ready ? OC.green : OC.dim2), fontSize: 10)),
            const SizedBox(height: 3),
            OStatBars(power: ds.power, accuracy: ds.accuracy),
          ]),
        ),
        if (canKick)
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_rounded, color: OC.red, size: 18),
            onPressed: busy.isEmpty ? () => _kick(uid) : null,
          ),
      ]),
    );
  }

  Widget _actionBar(BuildContext context) {
    final Room r = room!;
    final bool isHost = r.host == me;
    final bool playing = r.status == 'playing';
    final RoomPlayer? mp = st.player(me);
    final bool amPlayer = mp?.isPlayer ?? false;
    final bool full = _full;
    final List<RoomPlayer> notReady = _notReady;
    // v3: the host can start once every seated player is ready — empty seats are played by the bot
    final bool canStart = isHost && amPlayer && notReady.isEmpty && r.status == 'waiting';
    final List<Widget> top = <Widget>[];
    Widget? main;
    if (playing) {
      top.add(OBtn(context.ot('lobby.join_live_match'), style: OBtnStyle.red, onTap: () {
        final String m = r.currentMatch ?? '';
        if (m.isNotEmpty) _goMatch(m);
      }));
    } else if (r.kind == 'quick' || r.kind == 'arena') {
      final int np = st.players.where((RoomPlayer p) => p.isPlayer).length;
      top.add(Text(
        full ? context.ot('lobby.ready_to_start') : context.otf('lobby.searching_for_opponents_x_x', <Object>[context.fn(np), context.fn(teamSizeOf(r.mode) * 2)]),
        textAlign: TextAlign.center,
        style: const TextStyle(color: OC.cyan, fontWeight: FontWeight.w800),
      ));
    } else if (isHost) {
      final String reason = notReady.isNotEmpty
          ? context.otf('lobby.waiting_for_x_player_s', <Object>[context.fn(notReady.length)])
          : (!full ? context.ot('m3.bots_fill') : '');
      if (reason.isNotEmpty) top.add(Text(reason, textAlign: TextAlign.center, style: const TextStyle(color: OC.dim, fontSize: 11)));
      main = OBtn(busy == 'start' ? context.ot('lobby.starting') : context.ot('lobby.start_match'),
          style: canStart ? OBtnStyle.gold : OBtnStyle.dark, onTap: canStart && busy.isEmpty ? _start : null);
    } else if (amPlayer) {
      final bool rd = mp?.ready ?? false;
      main = OBtn(rd ? context.ot('lobby.i_m_ready') : context.ot('lobby.ready_up'),
          style: rd ? OBtnStyle.green : OBtnStyle.primary, onTap: busy.isEmpty ? _readyToggle : null);
    } else {
      top.add(Text(context.ot('lobby.tap_an_empty_slot_to'), textAlign: TextAlign.center, style: const TextStyle(color: OC.dim, fontSize: 12)));
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: const BoxDecoration(color: Color(0xF202040E), boxShadow: <BoxShadow>[BoxShadow(color: Color(0x99000000), blurRadius: 16)]),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        for (final Widget w in top) ...<Widget>[w, const SizedBox(height: 8)],
        Row(children: <Widget>[
          if (main != null) Expanded(child: main) else const Spacer(),
          const SizedBox(width: 8),
          SizedBox(
            width: 120,
            child: OBtn(context.ot('m3.leave'), style: OBtnStyle.dark, onTap: _askLeave),
          ),
        ]),
      ]),
    );
  }
}

// ---------------------------------------------------------------- room settings (host)
class _RoomSettingsSheet extends StatefulWidget {
  const _RoomSettingsSheet({required this.room, required this.link, required this.onDone});
  final Room room;
  final RoomLink link;
  final VoidCallback onDone;

  @override
  State<_RoomSettingsSheet> createState() => _RoomSettingsSheetState();
}

class _RoomSettingsSheetState extends State<_RoomSettingsSheet> {
  late final TextEditingController _name = TextEditingController(text: widget.room.name);
  late String rule = settingsToRule(widget.room.settings);
  late int turn = widget.room.settings['turn'] is num ? (widget.room.settings['turn'] as num).toInt() : 15;
  late int field = oi(widget.room.settings['field']);
  late String mode = widget.room.mode;
  bool busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => busy = true);
    final Map<String, dynamic> ns = <String, dynamic>{...widget.room.settings, ...ruleToSettings(rule), 'turn': turn, 'field': field};
    String nm = _name.text.trim();
    if (nm.length > 40) nm = nm.substring(0, 40);
    final Map<String, dynamic> args = <String, dynamic>{'p_room': widget.room.id, 'p_settings': ns, 'p_name': nm};
    // mode change: update_room(p_room, p_settings, p_name, p_mode) — same call as the Godot lobby
    if (mode != widget.room.mode) args['p_mode'] = mode;
    final OnlineResult r = await callRpc('update_room', args);
    if (!mounted) return;
    setState(() => busy = false);
    if (r.ok) {
      widget.link.ping();
      await widget.link.refresh();
      if (!mounted) return;
      otoast(context, context.ot('lobby.settings_saved'));
      widget.onDone();
    } else {
      otoast(context, r.error, err: true);
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          oCap(context.ot('hub.room_name')),
          TextField(
            controller: _name,
            maxLength: 40,
            style: const TextStyle(color: OC.text),
            decoration: InputDecoration(
              counterText: '',
              filled: true,
              fillColor: const Color(0x22FFFFFF),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
          oCap(context.ot('hub.mode')),
          OSegment<String>(
            items: <(String, String)>[for (final String m in kModes) (m, modeLabel(context, m))],
            value: mode,
            accent: OC.sky,
            onChanged: (String v) => setState(() => mode = v),
          ),
          oCap(context.ot('lobby.match_rule')),
          OSegment<String>(
            items: <(String, String)>[for (final List<String> r in kRules) (r[0], context.tx(r[1], r[2]))],
            value: rule,
            accent: OC.violet,
            onChanged: (String v) => setState(() => rule = v),
          ),
          oCap(context.ot('hub.turn_time')),
          OSegment<int>(
            items: <(int, String)>[for (final List<Object> t in kTurns) (t[0] as int, context.tx('${t[1]}', '${t[2]}'))],
            value: turn,
            accent: OC.green,
            onChanged: (int v) => setState(() => turn = v),
          ),
          oCap(context.ot('hub.field')),
          FieldPicker(value: field, onChanged: (int i) => setState(() => field = i)),
          const SizedBox(height: 16),
          OBtn(busy ? context.ot('lobby.saving') : context.ot('lobby.save'), busy: busy, onTap: _save),
        ]),
      );
}
