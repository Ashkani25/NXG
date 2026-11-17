import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nexora/app/router.dart';
import 'package:nexora/core/ui2/nx2_widgets.dart';
import 'package:nexora/worlds/personal_orbit/personal_orbit_page.dart';
import 'package:nexora/worlds/social_hub/social_hub_page.dart';

Widget _page(String name, Nx2Tab tab) => Scaffold(
      body: Center(child: Text('page:$name')),
      bottomNavigationBar: Nx2Dock(current: tab),
    );

void main() {
  test('dock has exactly five destinations with one path each', () {
    expect(Nx2Tab.values.length, 5);
    final Set<String> paths = Nx2Tab.values.map(nx2TabPath).toSet();
    expect(paths.length, 5, reason: 'two tabs must never open the same page');
    expect(nx2TabPath(Nx2Tab.home), '/hub');
    expect(nx2TabPath(Nx2Tab.games), '/rooms');
  });

  test('old entry points redirect to their single home', () {
    expect(legacyRedirect(Uri.parse('/rewards')), '/world/personal_orbit?tab=rewards');
    expect(legacyRedirect(Uri.parse('/world/nova_gallery')), '/social?tab=feed');
    expect(legacyRedirect(Uri.parse('/world/orbit_network')), '/social?tab=chats');
    expect(legacyRedirect(Uri.parse('/world/social_station')), '/social?tab=communities');
    expect(legacyRedirect(Uri.parse('/hub')), isNull);
    expect(legacyRedirect(Uri.parse('/world/nexora_exchange')), isNull);
  });

  test('tab query ids map to indexes', () {
    expect(SocialHubPage.tabIndex('chats'), 1);
    expect(SocialHubPage.tabIndex('communities'), 2);
    expect(SocialHubPage.tabIndex(null), 0);
    expect(PersonalOrbitPage.tabIndex('rewards'), 1);
    expect(PersonalOrbitPage.tabIndex('nope'), 0);
  });

  testWidgets('tapping dock destinations navigates (LTR and RTL)', (WidgetTester tester) async {
    for (final TextDirection dir in TextDirection.values) {
      final GoRouter router = GoRouter(initialLocation: '/hub', routes: <RouteBase>[
        GoRoute(path: '/hub', builder: (_, __) => _page('home', Nx2Tab.home)),
        GoRoute(path: '/social', builder: (_, __) => _page('social', Nx2Tab.social)),
        GoRoute(path: '/rooms', builder: (_, __) => _page('play', Nx2Tab.games)),
        GoRoute(path: '/world/nexora_exchange', builder: (_, __) => _page('shop', Nx2Tab.shop)),
        GoRoute(path: '/world/personal_orbit', builder: (_, __) => _page('profile', Nx2Tab.profile)),
      ]);
      await tester.pumpWidget(MaterialApp.router(
        routerConfig: router,
        builder: (BuildContext context, Widget? child) => Directionality(textDirection: dir, child: child!),
      ));
      await tester.pumpAndSettle();
      expect(find.text('page:home'), findsOneWidget);
      for (final String label in <String>['Home', 'Social', 'Shop', 'Profile']) {
        expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
      }
      expect(find.bySemanticsLabel('PLAY'), findsOneWidget);

      await tester.tap(find.text('Shop'));
      await tester.pumpAndSettle();
      expect(find.text('page:shop'), findsOneWidget);
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      expect(find.text('page:profile'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('PLAY'));
      await tester.pumpAndSettle();
      expect(find.text('page:play'), findsOneWidget);
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(find.text('page:home'), findsOneWidget);
      router.dispose();
    }
  });
}
