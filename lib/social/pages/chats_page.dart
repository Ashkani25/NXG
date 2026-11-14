import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/settings/app_settings.dart';
import '../../online/ui/oui.dart';
import '../social_models.dart';
import '../social_repository.dart';
import '../social_ui.dart';

String _clock(DateTime t) {
  final DateTime l = t.toLocal();
  return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

/// /social/chats — conversation list (live `inbox` view), refreshed by realtime.
class SocialChatsPage extends StatelessWidget {
  const SocialChatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return OPage(
      title: context.tx('گفتگوها', 'Chats'),
      en: 'CHATS',
      accent: OC.green,
      actions: <Widget>[
        IconButton(
          icon: const Icon(Icons.person_add_alt_1_rounded, color: OC.green),
          tooltip: context.tx('گفتگو با دوست', 'Chat with a friend'),
          onPressed: () => context.push('/social/friends'),
        ),
      ],
      body: SocialGate(builder: (BuildContext context, String me) => _InboxBody(key: ValueKey<String>(me), me: me)),
    );
  }
}

class _InboxBody extends StatefulWidget {
  const _InboxBody({super.key, required this.me});
  final String me;

  @override
  State<_InboxBody> createState() => _InboxBodyState();
}

class _InboxBodyState extends State<_InboxBody> {
  final SocialRepository repo = SocialRepository.instance;
  List<InboxItem>? _items;
  String _error = '';
  RealtimeChannel? _ch;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
    _ch = repo.watchInbox(() {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 600), _load);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    repo.unwatch(_ch);
    super.dispose();
  }

  Future<void> _load() async {
    final SocialResult<List<InboxItem>> r = await repo.inbox();
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _items = r.value;
        _error = '';
      } else {
        _error = r.error;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<InboxItem>? items = _items;
    if (items == null) {
      if (_error.isNotEmpty) return Center(child: OError(_error, onRetry: _load));
      return Padding(padding: const EdgeInsets.all(14), child: oSkeleton());
    }
    if (items.isEmpty) {
      return Center(
        child: OEmpty(
          icon: Icons.forum_outlined,
          title: context.tx('هنوز گفتگویی نداری', 'No conversations yet'),
          sub: context.tx('از صفحه‌ی دوستان یک گفتگو شروع کن', 'Start one from the Friends page'),
          action: context.tx('دوستان', 'Friends'),
          onAction: () => context.push('/social/friends'),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
        itemCount: items.length,
        itemBuilder: (BuildContext context, int i) => _InboxRow(item: items[i], me: widget.me, onReturn: _load),
      ),
    );
  }
}

class _InboxRow extends StatelessWidget {
  const _InboxRow({required this.item, required this.me, required this.onReturn});
  final InboxItem item;
  final String me;
  final Future<void> Function() onReturn;

  IconData get _kindIcon {
    switch (item.kind) {
      case 'dm':
        return Icons.person_rounded;
      case 'club':
        return Icons.shield_rounded;
      case 'channel':
        return Icons.campaign_rounded;
      default:
        return Icons.groups_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final String title = item.displayTitle(context.tx('گفتگو', 'Conversation'));
    final String last = item.lastBody == null
        ? context.tx('بدون پیام', 'No messages')
        : '${item.lastSender == me ? context.tx('تو: ', 'You: ') : ''}${item.lastBody}';
    final bool online = item.peer?.isOnlineAt(DateTime.now()) ?? false;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: OPanel(
        pad: 10,
        accent: item.unread > 0 ? OC.green : null,
        onTap: () async {
          await context.push('/social/chats/${item.id}');
          await onReturn();
        },
        child: Row(children: <Widget>[
          item.isDm
              ? OAvatar(disc: item.peer?.avatar, url: item.displayAvatarUrl, size: 46, dot: online ? OC.green : null)
              : Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: OC.violet.withValues(alpha: .18), border: Border.all(color: OC.violet)),
                  child: Icon(_kindIcon, color: OC.violet),
                ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: <Widget>[
              Text(title,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: OC.text, fontWeight: FontWeight.w800, fontSize: 14)),
              const SizedBox(height: 2),
              Text(last,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: item.unread > 0 ? OC.text : OC.dim, fontSize: 12)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: <Widget>[
            if (item.lastMessageAt != null) Text(timeAgo(context, item.lastMessageAt!.toIso8601String()), style: const TextStyle(color: OC.dim, fontSize: 10)),
            if (item.unread > 0) ...<Widget>[
              const SizedBox(height: 4),
              OBadge(context.fn(item.unread), color: OC.green),
            ],
            if (item.muted) const Icon(Icons.notifications_off_rounded, size: 14, color: OC.dim),
          ]),
        ]),
      ),
    );
  }
}

/// /social/chats/:id — one conversation, realtime messages + composer.
class SocialChatPage extends StatefulWidget {
  const SocialChatPage({super.key, required this.conversationId});
  final String conversationId;

  @override
  State<SocialChatPage> createState() => _SocialChatPageState();
}

class _SocialChatPageState extends State<SocialChatPage> {
  String _title = '';

  @override
  Widget build(BuildContext context) {
    return OPage(
      title: _title.isEmpty ? context.tx('گفتگو', 'Chat') : _title,
      en: 'CHAT',
      accent: OC.green,
      body: SocialGate(
        builder: (BuildContext context, String me) => _ChatBody(
          key: ValueKey<String>('${widget.conversationId}:$me'),
          conversationId: widget.conversationId,
          me: me,
          onTitle: (String t) {
            if (mounted && t != _title) setState(() => _title = t);
          },
        ),
      ),
    );
  }
}

class _ChatBody extends StatefulWidget {
  const _ChatBody({super.key, required this.conversationId, required this.me, required this.onTitle});
  final String conversationId;
  final String me;
  final ValueChanged<String> onTitle;

  @override
  State<_ChatBody> createState() => _ChatBodyState();
}

class _ChatBodyState extends State<_ChatBody> {
  final SocialRepository repo = SocialRepository.instance;
  final TextEditingController _text = TextEditingController();
  final ScrollController _scroll = ScrollController();
  List<ChatMessage>? _msgs;
  final Map<String, SocialProfile> _people = <String, SocialProfile>{};
  InboxItem? _conv;
  bool _canPost = true;
  bool _sending = false;
  String _error = '';
  RealtimeChannel? _ch;

  @override
  void initState() {
    super.initState();
    _load();
    _ch = repo.watchMessages(widget.conversationId, _onLive);
  }

  @override
  void dispose() {
    repo.unwatch(_ch);
    repo.markRead(widget.conversationId);
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final SocialResult<InboxItem?> c = await repo.conversation(widget.conversationId);
    final SocialResult<List<ChatMessage>> m = await repo.messages(widget.conversationId);
    final SocialResult<bool> cp = await repo.canPost(widget.conversationId);
    if (!mounted) return;
    if (!m.ok) {
      setState(() => _error = m.error);
      return;
    }
    final List<ChatMessage> list = m.value ?? <ChatMessage>[];
    await _ensurePeople(list.map((ChatMessage x) => x.sender).whereType<String>().toList());
    if (!mounted) return;
    setState(() {
      _conv = c.value;
      _msgs = list;
      _canPost = cp.value ?? true;
      _error = '';
    });
    final InboxItem? conv = c.value;
    if (conv != null) widget.onTitle(conv.displayTitle(''));
    repo.markRead(widget.conversationId);
    _toBottom();
  }

  Future<void> _ensurePeople(List<String> ids) async {
    final List<String> missing = ids.where((String id) => !_people.containsKey(id)).toSet().toList();
    if (missing.isEmpty) return;
    final SocialResult<Map<String, SocialProfile>> r = await repo.profilesFor(missing);
    final Map<String, SocialProfile>? v = r.value;
    if (v != null) _people.addAll(v);
  }

  Future<void> _onLive(ChatMessage m) async {
    final String? s = m.sender;
    if (s != null) await _ensurePeople(<String>[s]);
    if (!mounted) return;
    setState(() => _msgs = mergeMessage(_msgs ?? <ChatMessage>[], m));
    if (m.sender != widget.me) repo.markRead(widget.conversationId);
    _toBottom();
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send() async {
    final String body = _text.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    final SocialResult<ChatMessage> r = await repo.send(widget.conversationId, body);
    if (!mounted) return;
    setState(() {
      _sending = false;
      final ChatMessage? m = r.value;
      if (r.ok && m != null) {
        _text.clear();
        _msgs = mergeMessage(_msgs ?? <ChatMessage>[], m);
      }
    });
    if (!r.ok) {
      socialToast(context, false, r.error);
    } else {
      _toBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<ChatMessage>? msgs = _msgs;
    if (msgs == null) {
      if (_error.isNotEmpty) return Center(child: OError(_error, onRetry: _load));
      return oSpinner();
    }
    final bool group = !(_conv?.isDm ?? true);
    return Column(children: <Widget>[
      Expanded(
        child: msgs.isEmpty
            ? Center(child: OEmpty(icon: Icons.waving_hand_rounded, title: context.tx('اولین پیام را بفرست', 'Send the first message')))
            : ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                itemCount: msgs.length,
                itemBuilder: (BuildContext context, int i) {
                  final ChatMessage m = msgs[i];
                  final bool mine = m.mine(widget.me);
                  final bool showName = group && !mine && (i == 0 || msgs[i - 1].sender != m.sender);
                  return _Bubble(msg: m, mine: mine, author: showName ? _people[m.sender ?? ''] : null);
                },
              ),
      ),
      _canPost
          ? _composer(context)
          : Padding(
              padding: const EdgeInsets.all(14),
              child: Text(context.tx('در این گفتگو اجازه‌ی ارسال پیام نداری', 'You cannot post in this conversation'),
                  textAlign: TextAlign.center, style: const TextStyle(color: OC.dim)),
            ),
    ]);
  }

  Widget _composer(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
      decoration: const BoxDecoration(color: Color(0xCC0A102C), border: Border(top: BorderSide(color: OC.line))),
      child: Row(children: <Widget>[
        Expanded(
          child: TextField(
            controller: _text,
            minLines: 1,
            maxLines: 4,
            maxLength: 2000,
            textInputAction: TextInputAction.send,
            onSubmitted: (String _) => _send(),
            style: const TextStyle(color: OC.text),
            decoration: InputDecoration(
              counterText: '',
              hintText: context.tx('پیام…', 'Message…'),
              hintStyle: const TextStyle(color: OC.dim),
              filled: true,
              fillColor: const Color(0x22FFFFFF),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
            ),
          ),
        ),
        SocialIconBtn(icon: Icons.send_rounded, tooltip: context.tx('ارسال', 'Send'), color: OC.green, busy: _sending, onTap: _send),
      ]),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.msg, required this.mine, this.author});
  final ChatMessage msg;
  final bool mine;
  final SocialProfile? author;

  @override
  Widget build(BuildContext context) {
    final Color c = mine ? OC.cyan : OC.violet;
    final SocialProfile? a = author;
    return Align(
      alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .78),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          decoration: BoxDecoration(
            color: c.withValues(alpha: mine ? .22 : .14),
            borderRadius: BorderRadiusDirectional.only(
              topStart: const Radius.circular(16),
              topEnd: const Radius.circular(16),
              bottomStart: Radius.circular(mine ? 16 : 4),
              bottomEnd: Radius.circular(mine ? 4 : 16),
            ),
            border: Border.all(color: c.withValues(alpha: .4)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: <Widget>[
            if (a != null)
              GestureDetector(
                onTap: () => context.push('/social/user/${a.id}'),
                child: Text(a.displayName, style: const TextStyle(color: OC.violet, fontSize: 11, fontWeight: FontWeight.w800)),
              ),
            if ((msg.body ?? '').isNotEmpty) Text(msg.body!, style: const TextStyle(color: OC.text, fontSize: 14, height: 1.35)),
            if (msg.imageUrl != null && msg.imageUrl!.startsWith('http'))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(msg.imageUrl!, cacheWidth: 600, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_rounded, color: OC.dim)),
                ),
              ),
            const SizedBox(height: 2),
            Text(_clock(msg.createdAt), style: const TextStyle(color: OC.dim2, fontSize: 9)),
          ]),
        ),
      ),
    );
  }
}
