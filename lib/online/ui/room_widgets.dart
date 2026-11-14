/// Room widgets shared by the lobby and the online match: ping badge, voice bar, chat panel
/// (Godot ui_bits.gd PingBadge / VoiceBar / ChatPanel).
library;

import 'package:flutter/material.dart';

import '../../core/settings/app_settings.dart';
import '../link.dart';
import '../voice.dart';
import 'oui.dart';

// ---------------------------------------------------------------- ping badge
/// green < 80 ms, yellow < 150 ms, red otherwise (reads link.state.rtt)
class OPingBadge extends StatelessWidget {
  const OPingBadge(this.link, {super.key});
  final RoomLink link;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: link,
        builder: (BuildContext context, _) {
          final LinkState st = link.state;
          final int? r = st.rtt;
          final Color c = !st.connected ? OC.red : (r == null ? OC.dim : (r < 80 ? OC.green : (r < 150 ? OC.gold : OC.red)));
          final String t = !st.connected ? context.tx('قطع', 'offline') : (r == null ? '— ms' : '$r ms');
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: c.withValues(alpha: .14), borderRadius: BorderRadius.circular(10), border: Border.all(color: c.withValues(alpha: .5))),
            child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
              Icon(Icons.wifi_rounded, size: 12, color: c),
              const SizedBox(width: 4),
              Text(t, textDirection: TextDirection.ltr, style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w800)),
            ]),
          );
        },
      );
}

// ---------------------------------------------------------------- voice bar
class OVoiceBar extends StatelessWidget {
  const OVoiceBar(this.link, {super.key, this.enabled = true, this.compact = false});
  final RoomLink link;
  final bool enabled;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return Text(context.ot('ui_bits.voice_chat_is_off_for'), style: const TextStyle(color: OC.dim2, fontSize: 12));
    }
    final String? why = voiceUnsupportedReason();
    if (why != null) return Text(why, style: const TextStyle(color: OC.dim, fontSize: 12));
    final VoiceSession v = link.voice;
    return ListenableBuilder(
      listenable: v,
      builder: (BuildContext context, _) {
        final VoiceState s = v.state;
        final bool on = s.status == VoiceStatus.on;
        final bool connecting = s.status == VoiceStatus.connecting;
        if (on) {
          return Row(children: <Widget>[
            _pill(Icons.close_rounded, OC.red, () => v.leave()),
            const SizedBox(width: 6),
            _pill(s.speaker ? Icons.volume_up_rounded : Icons.volume_off_rounded, s.speaker ? OC.cyan : OC.dim2, () => v.setSpeaker(!s.speaker)),
            const SizedBox(width: 6),
            if (s.canPublish) _pill(s.mic ? Icons.mic_rounded : Icons.mic_off_rounded, s.mic ? OC.green : OC.dim2, () => v.setMic(!s.mic)),
            if (!compact) ...<Widget>[
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  s.canPublish ? context.ot(s.mic ? 'ui_bits.mic_on' : 'ui_bits.mic_off') : context.ot('ui_bits.listener_only'),
                  style: const TextStyle(color: OC.dim, fontSize: 12),
                ),
              ),
            ],
          ]);
        }
        return Row(mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max, children: <Widget>[
          if (compact)
            _pill(connecting ? Icons.more_horiz_rounded : Icons.mic_rounded, OC.cyan, connecting ? null : () => v.join())
          else
            Expanded(
              child: OBtn(connecting ? '…' : context.ot('ui_bits.join_voice_chat'),
                  onTap: connecting ? null : () => v.join(), small: true, style: OBtnStyle.dark),
            ),
          if (s.status == VoiceStatus.error && (s.error ?? '').isNotEmpty && !compact) ...<Widget>[
            const SizedBox(width: 8),
            Flexible(child: Text(s.error!, style: const TextStyle(color: OC.red, fontSize: 11))),
          ],
        ]);
      },
    );
  }

  Widget _pill(IconData i, Color c, VoidCallback? f) => InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: f,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: c.withValues(alpha: .15), shape: BoxShape.circle, border: Border.all(color: c.withValues(alpha: .6))),
          child: Icon(i, color: c, size: 22),
        ),
      );
}

// ---------------------------------------------------------------- chat panel
/// Room chat over RoomLink broadcast 'chat'. Newest at the bottom, max 80 kept by the link.
class OChatPanel extends StatefulWidget {
  const OChatPanel(this.link, {super.key, this.compact = false});
  final RoomLink link;
  final bool compact;

  @override
  State<OChatPanel> createState() => _OChatPanelState();
}

class _OChatPanelState extends State<OChatPanel> {
  final TextEditingController _in = TextEditingController();
  final ScrollController _sc = ScrollController();
  int _last = -1;

  @override
  void initState() {
    super.initState();
    widget.link.chatOpen = true;
    widget.link.markRead();
    widget.link.addListener(_sync);
  }

  @override
  void dispose() {
    widget.link.removeListener(_sync);
    if (!widget.link.disposed) widget.link.chatOpen = false;
    _in.dispose();
    _sc.dispose();
    super.dispose();
  }

  void _sync() {
    if (!mounted) return;
    final int n = widget.link.state.chat.length;
    if (n != _last) {
      _last = n;
      widget.link.markRead();
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_sc.hasClients) _sc.jumpTo(_sc.position.maxScrollExtent);
      });
    }
  }

  void _send() {
    final String t = _in.text.trim();
    if (t.isEmpty) return;
    widget.link.sendChat(t);
    _in.clear();
    _sync();
  }

  @override
  Widget build(BuildContext context) {
    final List<ChatMsg> chat = widget.link.state.chat;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        SizedBox(
          height: widget.compact ? 220 : 340,
          child: chat.isEmpty
              ? Center(child: Text(context.ot('ui_bits.no_messages_yet_say_hi'), style: const TextStyle(color: OC.dim2, fontSize: 13)))
              : ListView.builder(
                  controller: _sc,
                  itemCount: chat.length,
                  itemBuilder: (BuildContext context, int i) => _bubble(chat[i]),
                ),
        ),
        const SizedBox(height: 8),
        Row(children: <Widget>[
          Expanded(
            child: TextField(
              controller: _in,
              maxLength: 200,
              style: const TextStyle(color: OC.text),
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                counterText: '',
                hintText: context.ot('ui_bits.message'),
                hintStyle: const TextStyle(color: OC.dim2),
                filled: true,
                fillColor: const Color(0x22FFFFFF),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(onPressed: _send, icon: const Icon(Icons.send_rounded)),
        ]),
      ]),
    );
  }

  Widget _bubble(ChatMsg c) {
    final bool mine = c.uid == widget.link.me;
    return Align(
      alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: mine ? OC.cyan.withValues(alpha: .22) : const Color(0x22FFFFFF),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          if (!mine) Text(c.name, style: const TextStyle(color: OC.cyan, fontSize: 10, fontWeight: FontWeight.w800)),
          Text(c.text, style: const TextStyle(color: OC.text, fontSize: 13)),
        ]),
      ),
    );
  }
}

