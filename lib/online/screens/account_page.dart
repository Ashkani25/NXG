/// Online account (port of the Godot app's src/screens/account.gd = RN Account.tsx +
/// OnlineProfileCard.tsx): e-mail sign-in / sign-up / guest upgrade / password reset / resend,
/// guest sign-in, username + bio edit, avatar (disc preset), level / league / XP history, sign-out,
/// and the password-recovery dialog. Tables: profiles, xp_events, leagues.
///
/// Embeddable pieces for other areas: [OnlineAccountPanel], [OnlineProfileCard].
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/settings/app_settings.dart';
import '../online_core.dart';
import '../supabase_client.dart';
import '../ui/oui.dart';

const Map<String, List<String>> _reasonFa = <String, List<String>>{
  'match': <String>['مسابقه‌ی آنلاین', 'Online match'],
  'tournament': <String>['جایزه‌ی تورنمنت', 'Tournament prize'],
  'challenge': <String>['چالش روزانه', 'Daily challenge'],
  'offline': <String>['برد مقابل ربات', 'Win vs bot'],
};

class OnlineAccountPage extends StatefulWidget {
  const OnlineAccountPage({super.key});

  @override
  State<OnlineAccountPage> createState() => _OnlineAccountPageState();
}

class _OnlineAccountPageState extends State<OnlineAccountPage> {
  @override
  void initState() {
    super.initState();
    OnlineCore.instance.boot();
    if (OnlineCore.instance.signedIn) OnlineCore.instance.refreshProfile();
    WidgetsBinding.instance.addPostFrameCallback((_) => maybeShowRecovery(context));
  }

  @override
  Widget build(BuildContext context) => OPage(
        title: context.ot('account.online_account'),
        en: 'ACCOUNT',
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
          children: const <Widget>[OnlineAccountPanel(), SizedBox(height: 12), OnlineProfileCard()],
        ),
      );
}

/// Opens the new-password dialog when a recovery link signed the user in.
void maybeShowRecovery(BuildContext context) {
  if (!OnlineCore.instance.recovery || !context.mounted) return;
  showDialog<void>(context: context, barrierDismissible: false, builder: (BuildContext c) => const _RecoveryDialog());
}

// ================================================================ account panel
class OnlineAccountPanel extends StatefulWidget {
  const OnlineAccountPanel({super.key});

  @override
  State<OnlineAccountPanel> createState() => _OnlineAccountPanelState();
}

class _OnlineAccountPanelState extends State<OnlineAccountPanel> {
  final OnlineCore core = OnlineCore.instance;
  String mode = 'up';
  final TextEditingController _email = TextEditingController();
  final TextEditingController _pass = TextEditingController();
  final TextEditingController _pass2 = TextEditingController();
  final TextEditingController _name = TextEditingController();
  bool editName = false;
  bool busy = false;
  String sent = '';
  String err = '';
  bool sureOut = false;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    _pass2.dispose();
    _name.dispose();
    super.dispose();
  }

  bool _done(OnlineResult r, [String okMsg = '']) {
    if (!r.ok) {
      err = r.error.isEmpty ? context.ot('kb.error') : r.error;
      buzz('heavy');
      return false;
    }
    err = '';
    if (okMsg.isNotEmpty) otoast(context, okMsg);
    buzz('success');
    return true;
  }

  Future<void> _submit() async {
    setState(() => err = '');
    final String em = _email.text.trim();
    if (!emailOk(em)) return setState(() => err = context.ot('account.invalid_email'));
    if (mode != 'forgot' && _pass.text.length < 6) return setState(() => err = context.ot('account.password_must_be_at_least'));
    if (mode == 'up' && _pass.text != _pass2.text) return setState(() => err = context.ot('account.passwords_don_t_match'));
    setState(() => busy = true);
    if (mode == 'forgot') {
      final OnlineResult r = await core.resetPassword(em);
      if (mounted && _done(r)) sent = 'reset';
    } else if (mode == 'in') {
      final OnlineResult r = await core.signInEmail(em, _pass.text);
      if (mounted && _done(r, context.ot('account.signed_in'))) _pass.clear();
    } else if (core.signedIn && core.isGuest) {
      final OnlineResult r = await core.upgrade(em, _pass.text);
      if (mounted && _done(r)) sent = 'upgrade';
    } else {
      final OnlineResult r = await core.signUpEmail(em, _pass.text);
      if (mounted && _done(r)) sent = os(r.map['info']) == 'confirm' ? 'confirm' : '';
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _saveName() async {
    setState(() => busy = true);
    final OnlineResult r = await core.setUsername(_name.text);
    if (!mounted) return;
    if (_done(r, context.ot('account.username_changed'))) editName = false;
    setState(() => busy = false);
  }

  Widget _field(TextEditingController c, String hint, {bool secret = false, int max = 120, bool ltr = true}) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: TextField(
          controller: c,
          obscureText: secret,
          maxLength: max,
          textDirection: ltr ? TextDirection.ltr : null,
          keyboardType: secret ? TextInputType.visiblePassword : (ltr ? TextInputType.emailAddress : TextInputType.text),
          style: const TextStyle(color: OC.text),
          decoration: InputDecoration(
            counterText: '',
            hintText: hint,
            hintStyle: const TextStyle(color: OC.dim2),
            filled: true,
            fillColor: const Color(0x22FFFFFF),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: core, builder: (BuildContext context, _) => _build(context));

  Widget _build(BuildContext context) {
    if (!core.ready) {
      return OPanel(
        accent: OC.cyan,
        child: Column(children: <Widget>[
          Text(context.ot('account.couldn_t_connect'), style: const TextStyle(color: OC.dim)),
          const SizedBox(height: 8),
          OBtn(context.tx('تلاش دوباره', 'Retry'), small: true, style: OBtnStyle.dark, onTap: () => core.boot()),
        ]),
      );
    }
    final String u = core.uid;
    final bool guest = core.isGuest;
    final Map<String, dynamic> prof = core.profile;
    final bool signedEmail = u.isNotEmpty && !guest;
    final String status = u.isEmpty
        ? context.ot('account.not_signed_in')
        : (guest ? context.otf('account.guest_x', <Object>[os(prof['username'])]) : '${core.email} · ${os(prof['username'])}');
    final List<Widget> kids = <Widget>[
      Row(children: <Widget>[
        if (prof.isNotEmpty)
          OAvatar(disc: os(prof['equipped_disc']).isNotEmpty ? prof['equipped_disc'] : prof['avatar'], url: prof['avatar_url'], size: 48)
        else
          const Icon(Icons.account_circle_rounded, size: 44, color: OC.cyan),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(context.ot('account.online_account'), style: const TextStyle(color: OC.text, fontSize: 15, fontWeight: FontWeight.w900)),
            Text(status, style: const TextStyle(color: OC.dim, fontSize: 11)),
          ]),
        ),
        if (prof.isNotEmpty)
          Text(context.otf('hub.level_x', <Object>[context.fn(oi(prof['level'], 1))]),
              style: const TextStyle(color: OC.gold, fontSize: 11, fontWeight: FontWeight.w800)),
      ]),
    ];
    if (prof.isNotEmpty) {
      if (editName) {
        kids.add(_field(_name, context.ot('account.new_username_3_to_20'), max: 20, ltr: false));
        kids.add(const SizedBox(height: 8));
        kids.add(Row(children: <Widget>[
          Expanded(child: OBtn(context.ot('lobby.save'), small: true, busy: busy, onTap: _saveName)),
          const SizedBox(width: 8),
          Expanded(
              child: OBtn(context.ot('nav.cancel'),
                  small: true, style: OBtnStyle.dark, onTap: () => setState(() {
                        editName = false;
                        err = '';
                      }))),
        ]));
      } else {
        kids.add(TextButton(
          onPressed: () => setState(() {
            _name.text = os(core.profile['username']);
            editName = true;
          }),
          child: Text(context.ot('account.change_username'), style: const TextStyle(color: OC.cyan, fontSize: 12)),
        ));
      }
    }
    if (sent.isNotEmpty) {
      final String msg = sent == 'reset'
          ? context.ot('account.a_password_reset_link_was')
          : (sent == 'upgrade' ? context.ot('account.a_confirmation_link_was_sent') : context.ot('account.your_account_was_created_open'));
      kids.add(Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: OC.green.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: OC.green.withValues(alpha: .33)),
        ),
        child: Column(children: <Widget>[
          Text(msg, style: const TextStyle(color: OC.text, fontSize: 12)),
          const SizedBox(height: 8),
          Row(children: <Widget>[
            if (sent == 'confirm') ...<Widget>[
              Expanded(
                child: OBtn(context.ot('account.resend'), small: true, style: OBtnStyle.dark, onTap: () async {
                  final OnlineResult r = await core.resend(_email.text);
                  if (mounted) setState(() => _done(r, context.ot('account.sent_again')));
                }),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: OBtn(context.ot('account.ok'), small: true, onTap: () => setState(() {
                    if (sent == 'confirm') mode = 'in';
                    sent = '';
                  })),
            ),
          ]),
        ]),
      ));
    } else if (!signedEmail) {
      kids.add(const SizedBox(height: 8));
      kids.add(OSegment<String>(
        items: <(String, String)>[
          ('up', guest ? context.ot('account.register_email') : context.ot('tournaments.sign_up')),
          ('in', context.ot('hub.join')),
          ('forgot', context.ot('account.forgot_password')),
        ],
        value: mode,
        onChanged: (String v) => setState(() {
          mode = v;
          err = '';
        }),
      ));
      final String hint = mode == 'up'
          ? (guest ? context.ot('account.register_an_email_to_keep') : context.ot('account.create_an_account_to_save'))
          : (mode == 'in'
              ? (guest ? context.ot('account.signing_in_to_another_account') : context.ot('account.sign_in_with_email_and'))
              : context.ot('account.enter_your_email_and_we'));
      kids.add(Padding(padding: const EdgeInsets.only(top: 8), child: Text(hint, style: const TextStyle(color: OC.dim, fontSize: 11))));
      kids.add(_field(_email, context.ot('kb.email')));
      if (mode != 'forgot') kids.add(_field(_pass, context.ot('account.password'), secret: true, max: 72));
      if (mode == 'up') kids.add(_field(_pass2, context.ot('account.repeat_password'), secret: true, max: 72));
      if (err.isNotEmpty) kids.add(Padding(padding: const EdgeInsets.only(top: 8), child: Text(err, style: const TextStyle(color: OC.red, fontSize: 12))));
      String label = context.ot('account.send_link');
      if (mode == 'up') label = guest ? context.ot('account.register_email_keep_progress') : context.ot('account.create_account');
      if (mode == 'in') label = context.ot('hub.join');
      if (busy) label = context.ot('account.please_wait');
      kids.add(const SizedBox(height: 10));
      kids.add(OBtn(label, style: mode == 'in' ? OBtnStyle.primary : OBtnStyle.green, onTap: busy ? null : _submit));
      if (u.isEmpty) {
        kids.add(const SizedBox(height: 8));
        kids.add(OBtn(context.ot('account.continue_as_guest'), small: true, style: OBtnStyle.dark, onTap: busy
            ? null
            : () async {
                setState(() => busy = true);
                final String id = await core.ensure();
                if (!mounted) return;
                setState(() => busy = false);
                otoast(context, id.isNotEmpty ? context.ot('account.you_re_signed_in_as') : context.ot('account.couldn_t_connect'), err: id.isEmpty);
              }));
      }
    } else if (err.isNotEmpty) {
      kids.add(Text(err, style: const TextStyle(color: OC.red, fontSize: 12)));
    }
    if (u.isNotEmpty) {
      kids.add(const SizedBox(height: 10));
      kids.add(OBtn(
        sureOut ? (guest ? context.ot('account.guest_progress_will_be_lost') : context.ot('account.are_you_sure_tap_again')) : context.ot('account.sign_out'),
        small: true,
        style: OBtnStyle.red,
        onTap: () async {
          if (!sureOut) return setState(() => sureOut = true);
          sureOut = false;
          await core.signOut();
          if (mounted) otoast(context, context.ot('account.you_signed_out'));
        },
      ));
    }
    return OPanel(accent: OC.cyan, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: kids));
  }
}

// ================================================================ online profile card
class OnlineProfileCard extends StatefulWidget {
  const OnlineProfileCard({super.key});

  @override
  State<OnlineProfileCard> createState() => _OnlineProfileCardState();
}

class _OnlineProfileCardState extends State<OnlineProfileCard> {
  final OnlineCore core = OnlineCore.instance;
  List<Map<String, dynamic>>? events;
  int _lastXp = -1;
  bool editBio = false;
  bool connecting = false;
  final TextEditingController _bio = TextEditingController();

  @override
  void initState() {
    super.initState();
    core.loadLeagues().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _bio.dispose();
    super.dispose();
  }

  Future<void> _loadEvents() async {
    final String u = core.uid;
    if (u.isEmpty) return;
    _lastXp = oi(core.profile['xp'], -1);
    events = <Map<String, dynamic>>[];
    final OnlineResult r = await guard(() => Online.client
        .from('xp_events')
        .select('id,amount,reason,created_at')
        .eq('user_id', u)
        .order('created_at', ascending: false)
        .limit(10));
    if (!mounted) return;
    setState(() => events = r.rows);
  }

  Future<void> _saveBio() async {
    String b = _bio.text.trim();
    if (b.length > 160) b = b.substring(0, 160);
    final OnlineResult r = await core.patchProfile(<String, dynamic>{'bio': b.isNotEmpty ? b : null});
    if (!mounted) return;
    if (!r.ok) return otoast(context, r.error, err: true);
    setState(() => editBio = false);
    otoast(context, context.ot('account.saved'));
  }

  void _presetPicker() {
    final List<String> keys = <String>[for (int k = 0; k < 24; k++) 'club$k', for (int k = 0; k < 24; k++) 'nat$k'];
    showOSheet<void>(
      context,
      title: context.ot('account.choose_avatar'),
      en: 'AVATAR',
      builder: (BuildContext sc) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          Text(context.ot('account.choosing_a_photo_isn_t'), style: const TextStyle(color: OC.dim, fontSize: 12)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
            for (final String k in keys)
              GestureDetector(
                onTap: () async {
                  final OnlineResult r = await core.patchProfile(<String, dynamic>{'avatar': k, 'avatar_url': null});
                  if (!sc.mounted) return;
                  if (r.ok) {
                    otoast(context, context.ot('account.avatar_updated'));
                    Navigator.of(sc).pop();
                  } else {
                    otoast(context, r.error, err: true);
                  }
                },
                child: OAvatar(disc: k, size: 56, ring: OC.line),
              ),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: core, builder: (BuildContext context, _) => _build(context));

  Widget _build(BuildContext context) {
    final Map<String, dynamic> prof = core.profile;
    if (core.uid.isEmpty || prof.isEmpty) {
      return OPanel(
        accent: OC.cyan,
        child: Row(children: <Widget>[
          const Icon(Icons.public_rounded, size: 52, color: OC.cyan),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text(context.ot('account.online_profile'), style: const TextStyle(color: OC.text, fontSize: 16, fontWeight: FontWeight.w900)),
              Text(context.ot('account.level_league_and_online_stats'), style: const TextStyle(color: OC.dim, fontSize: 11)),
            ]),
          ),
          SizedBox(
            width: 84,
            child: OBtn(connecting ? '…' : context.ot('hub.join'), small: true, onTap: connecting
                ? null
                : () async {
                    setState(() => connecting = true);
                    final String id = await core.ensure();
                    if (!mounted) return;
                    setState(() => connecting = false);
                    if (id.isEmpty) otoast(context, context.ot('account.couldn_t_connect'), err: true);
                  }),
          ),
        ]),
      );
    }
    if (_lastXp != oi(prof['xp'], -1)) _loadEvents();
    final ({int level, int cur, int need, double frac}) lp = lvl(prof['xp']);
    final int rating = oi(prof['rating']);
    final (Map<String, dynamic>?, Map<String, dynamic>?) cn = leagueFor(rating);
    final Map<String, dynamic>? cur = cn.$1, nxt = cn.$2;
    final Color cc = cur != null ? leagueColor(cur) : OC.cyan;
    final int played = oi(prof['wins']) + oi(prof['losses']) + oi(prof['draws']);
    final String bio = os(prof['bio']);
    final List<Widget> out = <Widget>[
      OPanel(
        accent: cc,
        glow: true,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          Row(children: <Widget>[
            GestureDetector(
              onTap: _presetPicker,
              child: Stack(clipBehavior: Clip.none, children: <Widget>[
                OAvatar(disc: os(prof['equipped_disc']).isNotEmpty ? prof['equipped_disc'] : prof['avatar'], url: prof['avatar_url'], size: 76, ring: cc),
                const PositionedDirectional(
                  start: -2,
                  bottom: -2,
                  child: CircleAvatar(radius: 14, backgroundColor: Color(0xFF0E1640), child: Icon(Icons.edit_rounded, size: 14, color: OC.cyan)),
                ),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text(os(prof['username']), style: const TextStyle(color: OC.text, fontSize: 18, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Wrap(spacing: 4, runSpacing: 4, children: <Widget>[
                  OBadge(context.otf('hub.level_x', <Object>[context.fn(lp.level)]), color: OC.gold),
                  if (cur != null) OBadge(os(cur['name_fa']), color: cc),
                  if (core.isGuest) OBadge(context.ot('kb.guest'), color: OC.dim),
                ]),
                if (os(prof['avatar_url']).isNotEmpty)
                  TextButton(
                    onPressed: () async {
                      await core.patchProfile(<String, dynamic>{'avatar_url': null});
                      if (mounted) otoast(context, context.ot('account.photo_removed_your_active_disc'));
                    },
                    child: Text(context.ot('account.remove_photo'), style: const TextStyle(color: OC.dim, fontSize: 10)),
                  ),
              ]),
            ),
          ]),
          const SizedBox(height: 8),
          if (editBio) ...<Widget>[
            TextField(
              controller: _bio,
              maxLength: 160,
              maxLines: 3,
              style: const TextStyle(color: OC.text),
              decoration: InputDecoration(
                hintText: context.ot('account.a_few_words_about_yourself'),
                hintStyle: const TextStyle(color: OC.dim2),
                filled: true,
                fillColor: const Color(0x22FFFFFF),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
            Row(children: <Widget>[
              Expanded(child: OBtn(context.ot('lobby.save'), small: true, onTap: _saveBio)),
              const SizedBox(width: 8),
              Expanded(child: OBtn(context.ot('nav.cancel'), small: true, style: OBtnStyle.dark, onTap: () => setState(() => editBio = false))),
            ]),
          ] else
            InkWell(
              onTap: () => setState(() {
                _bio.text = os(core.profile['bio']);
                editBio = true;
              }),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(bio.isNotEmpty ? bio : context.ot('account.add_bio'),
                    style: TextStyle(color: bio.isNotEmpty ? const Color(0xFFD6E6FF) : OC.cyan, fontSize: 12)),
              ),
            ),
          OBar(lp.frac, color: OC.cyan, color2: OC.violet, h: 10),
          const SizedBox(height: 4),
          Text(context.otf('account.x_x_xp_to_level', <Object>[context.fn(lp.cur), context.fn(lp.need), context.fn(lp.level + 1)]),
              textAlign: TextAlign.center, style: const TextStyle(color: OC.dim, fontSize: 10)),
          const SizedBox(height: 10),
          Row(children: <Widget>[
            _stat(context.fn(rating), context.ot('online_result.rating')),
            _stat(context.fn(oi(prof['arena_points'])), context.ot('arena.arena')),
            _stat('🔥${context.fn(oi(prof['win_streak']))}', context.ot('arena.win_streak')),
            _stat(context.fn(played), context.ot('account.online_play')),
          ]),
        ]),
      ),
    ];
    if (cur != null) {
      double frac = 1;
      if (nxt != null) frac = (rating - oi(cur['min_rating'])) / math1(oi(nxt['min_rating']) - oi(cur['min_rating']));
      out.add(const SizedBox(height: 8));
      out.add(OPanel(
        accent: cc,
        onTap: () => context.push('/online/ranks?tab=leagues'),
        child: Row(children: <Widget>[
          leagueBadge(cur['id'], 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text(context.otf('ranks.x_league', <Object>[os(cur['name_fa'])]), style: TextStyle(color: cc, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              OBar(frac, color: cc, color2: OC.violet, h: 6),
              const SizedBox(height: 4),
              Text(
                nxt != null
                    ? context.otf('account.x_rating_to_x', <Object>[context.fn(oi(nxt['min_rating']) - rating), os(nxt['name_fa'])])
                    : context.ot('account.top_league'),
                style: const TextStyle(color: OC.dim, fontSize: 10),
              ),
            ]),
          ),
        ]),
      ));
    }
    out.add(oSection(context.ot('account.xp_history')));
    final List<Map<String, dynamic>>? ev = events;
    if (ev == null) {
      out.add(oSpinner());
    } else if (ev.isEmpty) {
      out.add(Text(context.ot('account.no_online_xp_yet_play'), textAlign: TextAlign.center, style: const TextStyle(color: OC.dim, fontSize: 12)));
    } else {
      for (final Map<String, dynamic> e in ev) {
        final String reason = os(e['reason']);
        final int amt = oi(e['amount']);
        out.add(Container(
          height: 44,
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: OC.line))),
          child: Row(children: <Widget>[
            Icon(reason == 'tournament' ? Icons.emoji_events_rounded : (reason == 'challenge' ? Icons.event_rounded : Icons.star_rounded),
                color: OC.gold, size: 22),
            const SizedBox(width: 8),
            Expanded(
                child: Text(_reasonFa[reason] != null ? context.tx(_reasonFa[reason]![0], _reasonFa[reason]![1]) : reason,
                    style: const TextStyle(color: OC.text, fontSize: 12))),
            Text(timeAgo(context, e['created_at']), style: const TextStyle(color: OC.dim, fontSize: 10)),
            const SizedBox(width: 8),
            Text('${amt >= 0 ? '+' : ''}${context.fn(amt)} XP',
                style: TextStyle(color: amt >= 0 ? OC.green : OC.red, fontSize: 12, fontWeight: FontWeight.w800)),
          ]),
        ));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: out);
  }

  Widget _stat(String v, String l) => Expanded(
        child: Column(children: <Widget>[
          Text(v, style: const TextStyle(color: OC.text, fontSize: 15, fontWeight: FontWeight.w900)),
          Text(l, textAlign: TextAlign.center, style: const TextStyle(color: OC.dim, fontSize: 10)),
        ]),
      );
}

double math1(int v) => v < 1 ? 1.0 : v.toDouble();

// ================================================================ password recovery (RN RecoveryModal)
class _RecoveryDialog extends StatefulWidget {
  const _RecoveryDialog();

  @override
  State<_RecoveryDialog> createState() => _RecoveryDialogState();
}

class _RecoveryDialogState extends State<_RecoveryDialog> {
  final TextEditingController p1 = TextEditingController();
  final TextEditingController p2 = TextEditingController();
  bool busy = false;
  String err = '';

  @override
  void dispose() {
    p1.dispose();
    p2.dispose();
    super.dispose();
  }

  Widget _f(TextEditingController c, String h) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: TextField(
          controller: c,
          obscureText: true,
          maxLength: 72,
          style: const TextStyle(color: OC.text),
          decoration: InputDecoration(
            counterText: '',
            hintText: h,
            hintStyle: const TextStyle(color: OC.dim2),
            filled: true,
            fillColor: const Color(0x22FFFFFF),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => AlertDialog(
        backgroundColor: const Color(0xF50A0F2C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: const BorderSide(color: OC.cyan)),
        title: Text(context.ot('account.new_password_2'), textAlign: TextAlign.center, style: const TextStyle(color: OC.text)),
        content: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          _f(p1, context.ot('account.new_password')),
          _f(p2, context.ot('account.repeat_new_password')),
          if (err.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err, style: const TextStyle(color: OC.red, fontSize: 12))),
          const SizedBox(height: 12),
          OBtn(context.ot('lobby.save'), busy: busy, onTap: () async {
            if (p1.text.length < 6) return setState(() => err = context.ot('account.password_must_be_at_least'));
            if (p1.text != p2.text) return setState(() => err = context.ot('account.passwords_don_t_match_2'));
            setState(() => busy = true);
            final OnlineResult r = await OnlineCore.instance.setNewPassword(p1.text);
            if (!mounted) return;
            setState(() => busy = false);
            if (!r.ok) return setState(() => err = r.error);
            otoast(context, context.ot('account.password_changed'));
            Navigator.of(context).pop();
          }),
          const SizedBox(height: 8),
          OBtn(context.ot('account.later'), small: true, style: OBtnStyle.dark, onTap: () {
            OnlineCore.instance.recovery = false;
            Navigator.of(context).pop();
          }),
        ]),
      );
}
