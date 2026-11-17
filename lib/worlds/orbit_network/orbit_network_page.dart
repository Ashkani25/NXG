import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/app_settings.dart';
import '../../core/theme/nx_theme.dart';
import '../../core/ui2/nx2_widgets.dart';
import '../../core/widgets/nx_widgets.dart';
import 'models/orbit_models.dart';
import 'state/orbit_controller.dart';
import 'ui/orbit_sheets.dart';
import 'ui/orbit_tabs.dart';

/// ORBIT NETWORK — the messenger world (offline-first).
class OrbitNetworkPage extends ConsumerStatefulWidget {
  const OrbitNetworkPage({super.key});

  @override
  ConsumerState<OrbitNetworkPage> createState() => _OrbitNetworkPageState();
}

class _OrbitNetworkPageState extends ConsumerState<OrbitNetworkPage>
    with WidgetsBindingObserver {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Pick up items other worlds shared while this page was closed.
    ref.read(orbitControllerProvider).refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed)
      ref.read(orbitControllerProvider).refresh();
  }

  Future<void> _newChat() async {
    final String? kind = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          ListTile(
            leading:
                const Icon(Icons.groups_rounded, color: NxColors.turquoise),
            title: Text(c.tx('گروه تازه', 'New group')),
            subtitle: Text(c.tx('گفت‌وگوی چندنفره با نشان باشگاه',
                'Multi-person chat with a club badge')),
            onTap: () => Navigator.pop(c, 'group'),
          ),
          ListTile(
            leading: const Icon(Icons.campaign_rounded,
                color: NxColors.electricBlue),
            title: Text(c.tx('کانال تازه', 'New channel')),
            subtitle:
                Text(c.tx('فقط مدیران منتشر می‌کنند', 'Only admins publish')),
            onTap: () => Navigator.pop(c, 'channel'),
          ),
          ListTile(
            leading: const Icon(Icons.person_add_alt_1_rounded,
                color: NxColors.textDim),
            title: Text(c.tx('چت خصوصی با دوست', 'Private chat with a friend')),
            subtitle: Text(ref.read(orbitControllerProvider).isOnline
                ? c.tx('از میان دوستانت', 'Pick one of your friends')
                : c.tx('بعد از اتصال آنلاین', 'Once online')),
            onTap: () => Navigator.pop(c, 'dm'),
          ),
        ]),
      ),
    );
    if (!mounted || kind == null) return;
    if (kind == 'dm') {
      setState(() => _tab = 2);
      return;
    }
    final OrbitChat? chat = await showOrbitChatEditor(
      context,
      kind: kind == 'channel' ? OrbitChatKind.channel : OrbitChatKind.group,
    );
    if (chat != null && mounted) openOrbitChat(context, chat.id);
  }

  Widget _body() {
    switch (_tab) {
      case 1:
        return const OrbitCallsTab(key: ValueKey<String>('calls'));
      case 2:
        return const OrbitContactsTab(key: ValueKey<String>('contacts'));
      default:
        return const OrbitChatsTab(key: ValueKey<String>('chats'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = ref.watch(orbitControllerProvider);
    final bool reduced = ref.watch(settingsProvider).reducedMotion;
    final NxThemeColors visual = NxThemeColors.of(context);
    final pal = WorldPalette.orbit;
    final int unread = ctrl.totalUnread;
    return NxWorldScaffold(
      title: 'ORBIT NETWORK',
      palette: pal,
      showWallet: false,
      actions: <Widget>[
        IconButton(
          tooltip: context.tx('جستجوی پیام‌ها', 'Search messages'),
          icon: const Icon(Icons.search_rounded),
          onPressed: () =>
              Navigator.of(context).push<void>(MaterialPageRoute<void>(
            builder: (BuildContext c) =>
                const OrbitMessageListPage(starredOnly: false),
          )),
        ),
        IconButton(
          tooltip: context.tx('ستاره‌دارها', 'Starred'),
          icon: const Icon(Icons.star_rounded),
          onPressed: () =>
              Navigator.of(context).push<void>(MaterialPageRoute<void>(
            builder: (BuildContext c) =>
                const OrbitMessageListPage(starredOnly: true),
          )),
        ),
        IconButton(
          tooltip: context.tx('صندوق اشتراک', 'Share inbox'),
          icon: Badge(
            isLabelVisible: ctrl.inboxItems.isNotEmpty,
            label: Text('${ctrl.inboxItems.length}'),
            child: const Icon(Icons.move_to_inbox_rounded),
          ),
          onPressed: () => showSharedInbox(context),
        ),
      ],
      floatingActionButton: _tab == 0
          ? FloatingActionButton(
              backgroundColor: visual.accent,
              foregroundColor: visual.background,
              tooltip: context.tx('گفت‌وگوی تازه', 'New chat'),
              onPressed: _newChat,
              child: const Icon(Icons.add_comment_rounded),
            )
          : null,
      body: Column(children: <Widget>[
        // Sections at the top (the old second bottom bar stacked above the dock). See docs/UI_AUDIT.md.
        Nx2SectionBar(
          index: _tab,
          onChanged: (int i) => setState(() => _tab = i),
          sections: <Nx2Section>[
            Nx2Section(Icons.chat_bubble_rounded, context.tx('گفت‌وگوها', 'Chats'), badge: unread),
            Nx2Section(Icons.call_rounded, context.tx('تماس‌ها', 'Calls')),
            Nx2Section(Icons.contacts_rounded, context.tx('مخاطبان و دوستان', 'Contacts & friends')),
          ],
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: reduced ? Duration.zero : NxMotion.normal,
            transitionBuilder: (Widget child, Animation<double> a) =>
                FadeTransition(opacity: a, child: child),
            child: _body(),
          ),
        ),
      ]),
    );
  }
}
