import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/profile/profile_service.dart';
import '../../../core/settings/app_settings.dart';
import '../../../core/theme/nx_theme.dart';
import '../../../core/widgets/nx_widgets.dart';
import '../models/orbit_models.dart';
import '../state/orbit_controller.dart';
import 'orbit_bubbles.dart';
import 'orbit_chat_page.dart';
import 'orbit_sheets.dart';

void openOrbitChat(BuildContext context, String chatId, {String? focusMessageId}) {
  Navigator.of(context).push<void>(MaterialPageRoute<void>(
    builder: (BuildContext c) => OrbitChatPage(chatId: chatId, focusMessageId: focusMessageId),
  ));
}

String _listTime(BuildContext context, DateTime t) {
  final now = DateTime.now();
  if (now.year == t.year && now.month == t.month && now.day == t.day) return orbitTime(t);
  return '${t.month}/${t.day}';
}

// ---------------------------------------------------------------- CHATS
class OrbitChatsTab extends ConsumerWidget {
  const OrbitChatsTab({super.key});

  Future<void> _chatMenu(BuildContext context, OrbitController ctrl, OrbitChat chat) async {
    final String? a = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          ListTile(
            leading: const Icon(Icons.push_pin_rounded),
            title: Text(chat.pinned ? c.tx('برداشتن سنجاق', 'Unpin') : c.tx('سنجاق', 'Pin')),
            onTap: () => Navigator.pop(c, 'pin'),
          ),
          ListTile(
            leading: Icon(chat.muted ? Icons.notifications_active_rounded : Icons.notifications_off_rounded),
            title: Text(chat.muted ? c.tx('صدادار', 'Unmute') : c.tx('بی‌صدا', 'Mute')),
            onTap: () => Navigator.pop(c, 'mute'),
          ),
          if (!chat.isSaved)
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: NxColors.danger),
              title: Text(c.tx('حذف گفت‌وگو', 'Delete chat'), style: const TextStyle(color: NxColors.danger)),
              onTap: () => Navigator.pop(c, 'delete'),
            ),
        ]),
      ),
    );
    switch (a) {
      case 'pin':
        chat.pinned = !chat.pinned;
        await ctrl.updateChat(chat);
        break;
      case 'mute':
        chat.muted = !chat.muted;
        await ctrl.updateChat(chat);
        break;
      case 'delete':
        await ctrl.deleteChat(chat.id);
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.watch(orbitControllerProvider);
    if (ctrl.loading) return const Center(child: CircularProgressIndicator());
    final pal = WorldPalette.orbit;
    final items = ctrl.inboxItems;
    return RefreshIndicator(
      onRefresh: ctrl.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(NxSpace.md, NxSpace.sm, NxSpace.md, 100),
        children: <Widget>[
          if (items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GlassPanel(
                tint: WorldPalette.nova.primary.withValues(alpha: 0.14),
                borderColor: WorldPalette.nova.primary.withValues(alpha: 0.5),
                onTap: () => showSharedInbox(context),
                child: Row(children: <Widget>[
                  Icon(Icons.move_to_inbox_rounded, color: WorldPalette.nova.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      context.tx('${items.length} مورد از دنیاهای دیگر برای ارسال آماده است',
                          '${items.length} item(s) from other worlds ready to send'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ]),
              ),
            ),
          for (final OrbitChatSummary s in ctrl.summaries)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GlassPanel(
                blur: false,
                padding: const EdgeInsets.all(10),
                tint: s.chat.isSaved ? pal.primary.withValues(alpha: 0.10) : const Color(0x14FFFFFF),
                onTap: () => openOrbitChat(context, s.chat.id),
                child: GestureDetector(
                  onLongPress: () => _chatMenu(context, ctrl, s.chat),
                  child: Row(children: <Widget>[
                    OrbitChatAvatar(chat: s.chat),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                        Row(children: <Widget>[
                          if (s.chat.isChannel)
                            const Padding(
                              padding: EdgeInsetsDirectional.only(end: 4),
                              child: Icon(Icons.campaign_rounded, size: 14, color: NxColors.textDim),
                            ),
                          Expanded(
                            child: Text(orbitChatTitle(context, s.chat),
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                          ),
                          if (s.chat.muted)
                            const Icon(Icons.notifications_off_rounded, size: 14, color: NxColors.textDim),
                          if (s.chat.pinned)
                            const Padding(
                              padding: EdgeInsetsDirectional.only(start: 4),
                              child: Icon(Icons.push_pin_rounded, size: 14, color: NxColors.gold),
                            ),
                          const SizedBox(width: 6),
                          Text(_listTime(context, s.last?.createdAt ?? s.chat.createdAt),
                              style: const TextStyle(fontSize: 11, color: NxColors.textDim)),
                        ]),
                        const SizedBox(height: 3),
                        Row(children: <Widget>[
                          Expanded(
                            child: Text(
                              s.last == null
                                  ? (s.chat.isSaved
                                      ? context.tx('یادداشت‌ها و ذخیره‌های تو', 'Your notes and saved things')
                                      : context.tx('هنوز پیامی نیست', 'No messages yet'))
                                  : (s.last!.kind == OrbitMessageKind.system
                                      ? context.tx('ساخته شد', 'Created')
                                      : s.last!.preview(fa: context.isFa)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: NxColors.textDim, fontSize: 13),
                            ),
                          ),
                          if (s.last != null && s.last!.authorId == ctrl.ownerId && s.last!.kind != OrbitMessageKind.system)
                            OrbitDeliveryIcon(delivery: s.last!.delivery),
                          if (s.unread > 0)
                            Container(
                              margin: const EdgeInsetsDirectional.only(start: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(color: pal.primary, borderRadius: BorderRadius.circular(10)),
                              child: Text('${s.unread}',
                                  style: const TextStyle(color: NxColors.navyDeep, fontSize: 11, fontWeight: FontWeight.w900)),
                            ),
                        ]),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
          if (ctrl.summaries.length <= 1)
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: Column(children: <Widget>[
                const OracleAvatar(pose: 'present', size: 86),
                const SizedBox(height: 8),
                GlassPanel(
                  child: Text(
                    context.tx(
                      'با دکمه‌ی + گروه یا کانال بساز. دوستانت بعد از اتصال آنلاین به گفت‌وگوها می‌پیوندند؛ تا آن زمان پیام‌ها روی دستگاهت صف می‌شوند.',
                      'Use + to create a group or channel. Friends join once you are online; until then messages queue on your device.',
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(height: 1.5),
                  ),
                ),
              ]),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- CALLS
class OrbitCallsTab extends StatelessWidget {
  const OrbitCallsTab({super.key});

  @override
  Widget build(BuildContext context) {
    Widget card(IconData icon, String fa, String en, String dfa, String den, Color color) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: GlassPanel(
            onTap: () => showOrbitOnlineOnly(context, fa: fa, en: en, icon: icon),
            child: Row(children: <Widget>[
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.18),
                  border: Border.all(color: color.withValues(alpha: 0.6)),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Text(context.tx(fa, en), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  Text(context.tx(dfa, den), style: const TextStyle(color: NxColors.textDim, fontSize: 12)),
                ]),
              ),
              const Icon(Icons.cloud_off_rounded, color: NxColors.gold, size: 18),
            ]),
          ),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(NxSpace.md, NxSpace.sm, NxSpace.md, 100),
      children: <Widget>[
        const OnlineOnlyNotice(featureFa: 'تماس صوتی، تصویری و گروهی', featureEn: 'Voice, video and group calls'),
        const SizedBox(height: 14),
        card(Icons.call_rounded, 'تماس صوتی', 'Voice call', 'صدای شفاف با هاله‌ی صوتی', 'Crystal voice with a reactive aura',
            NxColors.turquoise),
        card(Icons.videocam_rounded, 'تماس تصویری', 'Video call', 'رو در رو، در هر کجای کهکشان', 'Face to face, anywhere in the galaxy',
            NxColors.electricBlue),
        card(Icons.groups_rounded, 'تماس گروهی', 'Group call', 'گردهمایی صوتی و تصویری دوستان', 'Voice and video with your crew',
            NxColors.violet),
        const SizedBox(height: 20),
        Center(
          child: Column(children: <Widget>[
            const OracleAvatar(pose: 'calm', size: 80),
            const SizedBox(height: 8),
            Text(
              context.tx('تاریخچه‌ی تماس خالی است. هیچ تماسی شبیه‌سازی نمی‌شود.', 'Call history is empty. No call is ever simulated.'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: NxColors.textDim),
            ),
          ]),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- CONTACTS
class OrbitContactsTab extends ConsumerWidget {
  const OrbitContactsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ProfileService p = ref.watch(profileProvider);
    final String name = orbitMyName(context, p);
    final String shareText = context.tx(
      'در NEXORA پیدایم کن! شناسه‌ی کاوشگر من: ${p.explorerId} ($name)',
      'Find me in NEXORA! My Explorer ID: ${p.explorerId} ($name)',
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(NxSpace.md, NxSpace.sm, NxSpace.md, 100),
      children: <Widget>[
        GlassPanel(
          tint: WorldPalette.orbit.primary.withValues(alpha: 0.12),
          borderColor: WorldPalette.orbit.primary.withValues(alpha: 0.6),
          child: Column(children: <Widget>[
            Row(children: <Widget>[
              const Icon(Icons.fingerprint_rounded, color: NxColors.turquoise),
              const SizedBox(width: 8),
              Text(context.tx('کارت کاوشگر', 'Explorer ID card'), style: const TextStyle(fontWeight: FontWeight.w900)),
              const Spacer(),
              NxPill(label: 'Lv ${p.level}', color: NxColors.turquoise),
            ]),
            const SizedBox(height: 14),
            Text(name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Directionality(
              textDirection: TextDirection.ltr,
              child: SelectableText(
                p.explorerId,
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 3, color: NxColors.turquoise),
              ),
            ),
            const SizedBox(height: 4),
            Text(context.tx(p.rankTitleFa, p.rankTitleEn), style: const TextStyle(color: NxColors.textDim)),
            const SizedBox(height: 14),
            Row(children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: p.explorerId));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text(context.tx('شناسه کپی شد', 'ID copied'))));
                    }
                  },
                  icon: const Icon(Icons.copy_rounded),
                  label: Text(context.tx('کپی شناسه', 'Copy ID')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: NxColors.turquoise),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: shareText));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(context.tx('متن دعوت کپی شد؛ هرجا خواستی بفرست', 'Invite text copied; paste it anywhere'))));
                    }
                  },
                  icon: const Icon(Icons.share_rounded),
                  label: Text(context.tx('متن دعوت', 'Invite text')),
                ),
              ),
            ]),
          ]),
        ),
        const SizedBox(height: 14),
        const OnlineOnlyNotice(featureFa: 'دوستان، مخاطبان و وضعیت آنلاین', featureEn: 'Friends, contacts and online presence'),
        const SizedBox(height: 18),
        Center(
          child: Column(children: <Widget>[
            const OracleAvatar(pose: 'happy', size: 86),
            const SizedBox(height: 8),
            Text(
              context.tx(
                'دوستانت بعد از اتصال آنلاین اینجا ظاهر می‌شوند. شناسه‌ات را به اشتراک بگذار تا پیدایت کنند.',
                'Your friends appear here once NEXORA is online. Share your ID so they can find you.',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(color: NxColors.textDim, height: 1.5),
            ),
          ]),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- SEARCH / STARRED
class OrbitMessageListPage extends ConsumerStatefulWidget {
  const OrbitMessageListPage({super.key, required this.starredOnly});
  final bool starredOnly;

  @override
  ConsumerState<OrbitMessageListPage> createState() => _OrbitMessageListPageState();
}

class _OrbitMessageListPageState extends ConsumerState<OrbitMessageListPage> {
  List<OrbitMessage> _results = <OrbitMessage>[];
  String _q = '';

  @override
  void initState() {
    super.initState();
    if (widget.starredOnly) _load();
  }

  Future<void> _load() async {
    final ctrl = ref.read(orbitControllerProvider);
    final r = widget.starredOnly ? await ctrl.starred() : await ctrl.search(_q);
    if (mounted) setState(() => _results = r);
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = ref.watch(orbitControllerProvider);
    return NxWorldScaffold(
      title: widget.starredOnly ? context.tx('پیام‌های ستاره‌دار', 'STARRED') : context.tx('جستجوی پیام‌ها', 'SEARCH'),
      palette: WorldPalette.orbit,
      showWallet: false,
      body: Column(children: <Widget>[
        if (!widget.starredOnly)
          Padding(
            padding: const EdgeInsets.all(NxSpace.md),
            child: TextField(
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: context.tx('در همه‌ی گفت‌وگوها جستجو کن…', 'Search all chats…'),
              ),
              onChanged: (String v) {
                _q = v;
                _load();
              },
            ),
          ),
        Expanded(
          child: _results.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                    OracleAvatar(pose: widget.starredOnly ? 'sleep' : 'idle', size: 86),
                    const SizedBox(height: 8),
                    Text(
                      widget.starredOnly
                          ? context.tx('پیام ستاره‌داری نداری. پیام را نگه دار و «ستاره» را بزن.',
                              'No starred messages. Long-press a message and tap Star.')
                          : (_q.trim().isEmpty
                              ? context.tx('عبارتی بنویس.', 'Type something.')
                              : context.tx('نتیجه‌ای پیدا نشد.', 'No results.')),
                      style: const TextStyle(color: NxColors.textDim),
                    ),
                  ]),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: NxSpace.md),
                  itemCount: _results.length,
                  itemBuilder: (BuildContext c, int i) {
                    final m = _results[i];
                    final OrbitChat? chat = ctrl.chatById(m.chatId);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: GlassPanel(
                        blur: false,
                        padding: const EdgeInsets.all(10),
                        onTap: chat == null
                            ? null
                            : () async {
                                openOrbitChat(c, m.chatId, focusMessageId: m.id);
                              },
                        child: Row(children: <Widget>[
                          if (chat != null) OrbitChatAvatar(chat: chat, size: 36),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                              Text(chat == null ? '—' : orbitChatTitle(c, chat),
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                              Text(m.preview(fa: c.isFa), maxLines: 2, overflow: TextOverflow.ellipsis),
                            ]),
                          ),
                          Text(_listTime(c, m.createdAt), style: const TextStyle(fontSize: 11, color: NxColors.textDim)),
                        ]),
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}
