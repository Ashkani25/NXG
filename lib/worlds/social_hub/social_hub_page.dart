import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/profile/profile_service.dart';
import '../../core/profile/world_visits.dart';
import '../../core/settings/app_settings.dart';
import '../../core/ui2/nx2_widgets.dart';
import '../nova_gallery/nova_gallery_page.dart';
import '../orbit_network/orbit_network_page.dart';
import '../social_station/social_station_page.dart';

/// SOCIAL tab: the one home of everything social — Feed & stories (Nova Gallery), Chats (Orbit Network: chats,
/// calls, contacts/friends) and Communities (Social Station). Each sub-tab is the existing Supabase-backed screen.
/// `/world/nova_gallery|orbit_network|social_station` redirect here (`?tab=feed|chats|communities`).
class SocialHubPage extends ConsumerStatefulWidget {
  const SocialHubPage({super.key, this.initial = 0});
  final int initial;

  static const List<String> tabIds = <String>['feed', 'chats', 'communities'];
  static const List<String> _worldIds = <String>['nova_gallery', 'orbit_network', 'social_station'];

  /// `?tab=` value -> index (unknown -> Feed).
  static int tabIndex(String? id) {
    final int i = tabIds.indexOf(id ?? '');
    return i < 0 ? 0 : i;
  }

  @override
  ConsumerState<SocialHubPage> createState() => _SocialHubPageState();
}

class _SocialHubPageState extends ConsumerState<SocialHubPage> {
  late int _tab = widget.initial.clamp(0, 2);
  final Set<int> _built = <int>{};

  @override
  Widget build(BuildContext context) {
    if (_built.add(_tab)) {
      final int t = _tab;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) recordWorldVisit(ref.read(profileProvider), SocialHubPage._worldIds[t]);
      });
    }
    const List<Widget> pages = <Widget>[NovaGalleryPage(), OrbitNetworkPage(), SocialStationPage()];
    final List<(IconData, String)> tabs = <(IconData, String)>[
      (Icons.dynamic_feed_rounded, context.tx('پست و استوری', 'Feed & stories')),
      (Icons.forum_rounded, context.tx('گفت‌وگوها', 'Chats')),
      (Icons.groups_rounded, context.tx('جامعه‌ها', 'Communities')),
    ];
    final Widget nav = Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 2),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xE6140A36),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Nx2.cyan.withValues(alpha: 0.45)),
        ),
        child: Row(children: <Widget>[
          for (int i = 0; i < tabs.length; i++)
            Expanded(
              child: Semantics(
                button: true,
                selected: i == _tab,
                child: GestureDetector(
                  onTap: () => setState(() => _tab = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: i == _tab
                          ? const LinearGradient(colors: <Color>[Color(0xFF7B3CFF), Color(0xFFE040C8)])
                          : null,
                    ),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
                      Icon(tabs[i].$1, size: 17, color: i == _tab ? Colors.white : Nx2.muted),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(tabs[i].$2,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: i == _tab ? Colors.white : Nx2.muted)),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
    return Scaffold(
      backgroundColor: Nx2.deep,
      body: NxSubNav(
        nav: nav,
        child: IndexedStack(index: _tab, children: <Widget>[
          for (int i = 0; i < pages.length; i++) _built.contains(i) ? pages[i] : const SizedBox.shrink(),
        ]),
      ),
      bottomNavigationBar: const Nx2Dock(current: Nx2Tab.social),
    );
  }
}
