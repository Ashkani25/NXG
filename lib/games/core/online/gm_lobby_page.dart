/// Online lobby of one arcade game: quick match, create a room, join by code, public rooms,
/// my rating and the game's leaderboard.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:nexora/core/settings/app_settings.dart';
import 'package:nexora/core/theme/nx_theme.dart';
import 'package:nexora/core/widgets/nx_widgets.dart';
import 'package:nexora/online/online_core.dart';
import 'package:nexora/online/supabase_client.dart';

import 'gm_backend.dart';
import 'gm_models.dart';
import 'gm_room_page.dart';
import 'gm_widgets.dart';

class GmLobbyPage extends StatefulWidget {
  const GmLobbyPage({super.key, required this.gameId, this.backend});
  final String gameId;
  final GmBackend? backend;

  @override
  State<GmLobbyPage> createState() => _GmLobbyPageState();
}

class _GmLobbyPageState extends State<GmLobbyPage> {
  GmBackend get _b => widget.backend ?? const SupabaseGmBackend();
  GmGameSpec? get _spec => gmSpec(widget.gameId);

  bool _booting = true;
  bool _busy = false;
  String? _error;
  int _seats = 2;
  bool _private = false;
  final TextEditingController _code = TextEditingController();
  List<Map<String, dynamic>> _rooms = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _board = <Map<String, dynamic>>[];
  Map<String, dynamic>? _mine;

  @override
  void initState() {
    super.initState();
    _seats = _spec?.defaultSeats ?? 2;
    _boot();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    await OnlineCore.instance.boot();
    if (!mounted) return;
    setState(() => _booting = false);
    unawaited(_load());
  }

  Future<void> _load() async {
    if (!Online.ready) return;
    try {
      final List<Map<String, dynamic>> r = await _b.rooms(widget.gameId);
      final List<Map<String, dynamic>> lb = await _b.leaderboard(widget.gameId, limit: 10);
      final String me = OnlineCore.instance.uid;
      final Map<String, dynamic>? mine = me.isEmpty ? null : await _b.myRating(widget.gameId, me);
      if (!mounted) return;
      setState(() {
        _rooms = r;
        _board = lb;
        _mine = mine;
      });
    } catch (_) {/* lists are optional */}
  }

  String _err(Object e) => gmErrorText(errMessage(e), context.isFa);

  /// Signs in (guest) when needed, runs [f] and opens the room it returns.
  Future<void> _go(Future<Map<String, dynamic>> Function() f) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final String uid = await OnlineCore.instance.ensure();
    if (!mounted) return;
    if (uid.isEmpty) {
      setState(() {
        _busy = false;
        _error = context.tx('ورود به حساب آنلاین ممکن نشد', 'Could not sign in to your online account');
      });
      return;
    }
    try {
      final Map<String, dynamic> room = await f();
      if (!mounted) return;
      setState(() => _busy = false);
      final String rid = '${room['id'] ?? ''}';
      if (rid.isEmpty) return;
      final String game = '${room['game'] ?? ''}';
      if (game.isNotEmpty && game != widget.gameId) {
        // a code of another game's room (e.g. a football room): do not stay in it
        unawaited(_b.leave(rid).catchError((Object _) {}));
        final GmGameSpec? other = gmSpec(game);
        setState(() => _error = context.tx(
            'این کد مربوط به اتاق ${other?.nameFa ?? 'بازی دیگری'} است',
            'That code belongs to a ${other?.nameEn ?? 'different game'} room'));
        return;
      }
      OnlineCore.instance.enterRoom(room);
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (BuildContext _) => GmRoomPage(gameId: widget.gameId, roomId: rid, backend: widget.backend),
      ));
      if (mounted) unawaited(_load());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _err(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final GmGameSpec? spec = _spec;
    final String title = spec == null ? widget.gameId : context.tx('${spec.nameFa} آنلاین', '${spec.nameEn} online');
    return NxWorldScaffold(
      title: title,
      palette: WorldPalette.arcade,
      showWallet: false,
      actions: <Widget>[IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      body: _body(context, spec),
    );
  }

  Widget _body(BuildContext context, GmGameSpec? spec) {
    if (spec == null || !spec.playable) {
      return ListView(padding: const EdgeInsets.all(NxSpace.md), children: <Widget>[
        OnlineOnlyNotice(
          featureFa: 'نسخه‌ی آنلاین ${spec?.nameFa ?? 'این بازی'} (به‌زودی)',
          featureEn: 'Online ${spec?.nameEn ?? 'play for this game'} (coming soon)',
        ),
      ]);
    }
    if (_booting) return const Center(child: CircularProgressIndicator());
    if (!Online.ready) {
      return ListView(padding: const EdgeInsets.all(NxSpace.md), children: <Widget>[
        OnlineOnlyNotice(featureFa: 'بازی آنلاین ${spec.nameFa}', featureEn: 'Online ${spec.nameEn}'),
        const SizedBox(height: 12),
        FilledButton(onPressed: _boot, child: Text(context.tx('تلاش دوباره', 'Retry'))),
      ]);
    }
    final bool multi = spec.maxSeats > spec.minSeats;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(NxSpace.md), children: <Widget>[
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(_error!, style: const TextStyle(color: NxColors.danger)),
          ),
        _ratingCard(context),
        const SizedBox(height: 12),
        GlassPanel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
            Text(context.tx('بازی سریع', 'Quick match'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 4),
            Text(
              context.tx('با بازیکن‌های واقعی هم‌گروه می‌شوی؛ وقتی همه‌ی صندلی‌ها پر شد بازی خودکار شروع می‌شود.',
                  'You are matched with real players; the match starts by itself once every seat is taken.'),
              style: const TextStyle(color: NxColors.textDim, fontSize: 13),
            ),
            if (multi) ...<Widget>[
              const SizedBox(height: 8),
              _seatPicker(context, spec),
            ],
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _busy ? null : () => _go(() => _b.quick(widget.gameId, _seats)),
              icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.bolt_rounded),
              label: Text(context.tx('پیدا کن', 'Find a match')),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        GlassPanel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
            Text(context.tx('ساخت اتاق', 'Create a room'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            if (multi) ...<Widget>[const SizedBox(height: 8), _seatPicker(context, spec)],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _private,
              onChanged: (bool x) => setState(() => _private = x),
              title: Text(context.tx('اتاق خصوصی (فقط با کد)', 'Private room (code only)')),
              subtitle: Text(context.tx('اتاق‌های خصوصی رتبه‌ای نیستند', 'Private rooms are unranked'),
                  style: const TextStyle(fontSize: 12)),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _go(() => _b.createRoom(widget.gameId, _seats, private: _private)),
              icon: const Icon(Icons.add_rounded),
              label: Text(context.tx('بساز', 'Create')),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        GlassPanel(
          child: Row(children: <Widget>[
            Expanded(
              child: TextField(
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(hintText: context.tx('کد اتاق', 'Room code'), isDense: true),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _busy
                  ? null
                  : () {
                      final String code = _code.text.trim();
                      if (code.isEmpty) return;
                      _go(() => _b.joinRoom(code: code));
                    },
              child: Text(context.tx('ورود', 'Join')),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        Text(context.tx('اتاق‌های باز', 'Open rooms'), style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        if (_rooms.isEmpty)
          Text(context.tx('فعلاً اتاق بازی نیست؛ یکی بساز!', 'No open rooms right now — create one!'),
              style: const TextStyle(color: NxColors.textDim)),
        for (final Map<String, dynamic> r in _rooms) _roomTile(context, r),
        const SizedBox(height: 16),
        if (_board.isNotEmpty) ...<Widget>[
          Text(context.tx('برترین‌ها', 'Leaderboard'), style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          for (final Map<String, dynamic> e in _board)
            ListTile(
              dense: true,
              leading: Text(gmNum(context, gmInt(e['rank'])), style: const TextStyle(fontWeight: FontWeight.w900, color: NxColors.gold)),
              title: Text('${e['username'] ?? '…'}'),
              trailing: Text(gmNum(context, gmInt(e['rating'], 1000))),
            ),
        ],
      ]),
    );
  }

  Widget _ratingCard(BuildContext context) {
    final Map<String, dynamic>? m = _mine;
    return GlassPanel(
      child: Row(children: <Widget>[
        const Icon(Icons.military_tech_rounded, color: NxColors.gold, size: 32),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            m == null
                ? context.tx('هنوز مسابقه‌ی آنلاینی در این بازی نداری', 'No online matches in this game yet')
                : context.tx(
                    'امتیاز ${gmNum(context, gmInt(m['rating'], 1000))} • برد ${gmNum(context, gmInt(m['wins']))} • باخت ${gmNum(context, gmInt(m['losses']))}',
                    'Rating ${gmInt(m['rating'], 1000)} • W ${gmInt(m['wins'])} • L ${gmInt(m['losses'])}'),
          ),
        ),
      ]),
    );
  }

  Widget _seatPicker(BuildContext context, GmGameSpec spec) {
    return Wrap(spacing: 6, runSpacing: 6, children: <Widget>[
      for (final int n in spec.seatChoices)
        ChoiceChip(
          label: Text(context.tx('${gmNum(context, n)} نفره', '$n players')),
          selected: _seats == n,
          onSelected: (bool _) => setState(() => _seats = n),
        ),
    ]);
  }

  Widget _roomTile(BuildContext context, Map<String, dynamic> r) {
    final int players = gmInt(r['players']);
    final int cap = gmInt(r['capacity'], 2);
    final bool playing = r['status'] == 'playing';
    return Card(
      color: Colors.white.withValues(alpha: 0.06),
      child: ListTile(
        title: Text('${r['name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${r['host_name'] ?? '…'} • ${gmNum(context, players)}/${gmNum(context, cap)}'
          '${playing ? context.tx(' • در حال بازی', ' • playing') : ''}',
        ),
        trailing: FilledButton.tonal(
          onPressed: _busy
              ? null
              : () => _go(() => _b.joinRoom(roomId: '${r['id']}', spectate: playing || players >= cap)),
          child: Text(playing || players >= cap ? context.tx('تماشا', 'Watch') : context.tx('ورود', 'Join')),
        ),
      ),
    );
  }
}
