import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nexora/core/profile/profile_service.dart';
import 'package:nexora/core/settings/app_settings.dart';
import 'package:nexora/core/storage/local_store.dart';
import 'package:nexora/core/theme/nx_theme.dart';
import 'package:nexora/worlds/onboarding/onboarding_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{'settings.lang': 'en', 'settings.auth_mode': 'guest'});
    await LocalStore.init();
  });

  test('favourite games persist, deduplicated', () {
    final AppSettings s = AppSettings(LocalStore.instance);
    expect(s.favoriteGames, isEmpty);
    s.favoriteGames = <String>['uno', 'carrom', 'uno'];
    expect(AppSettings(LocalStore.instance).favoriteGames, <String>['uno', 'carrom']);
  });

  testWidgets('onboarding is three steps: language+look, identity, favourite games', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final ProviderContainer c = ProviderContainer();
    addTearDown(c.dispose);
    final GoRouter router = GoRouter(initialLocation: '/onboarding', routes: <RouteBase>[
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingPage()),
      GoRoute(path: '/hub', builder: (_, __) => const Scaffold(body: Text('HUB'))),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp.router(
        routerConfig: router,
        theme: buildNxTheme(light: false, highContrast: false),
        locale: const Locale('en'),
        supportedLocales: const <Locale>[Locale('fa'), Locale('en')],
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
      ),
    ));
    await tester.pump(const Duration(milliseconds: 600));
    final AppSettings s = c.read(settingsProvider);

    // Step 1: language + look.
    expect(find.text('1 of 3'), findsOneWidget);
    await tester.tap(find.text('Light'));
    await tester.pump();
    expect(s.themeMode, ThemeMode.light);
    await tester.tap(find.text('Continue'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));

    // Step 2: identity; a too-short name stays here.
    expect(find.text('2 of 3'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('2 of 3'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Ashkan');
    await tester.tap(find.text('Continue'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));

    // Step 3: favourite games (optional).
    expect(find.text('3 of 3'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('fav_uno')));
    await tester.pump();
    expect(find.text('Skip'), findsNothing);
    await tester.tap(find.text('Enter NEXORA'));
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    // The first identity may level up the profile: close the award dialog if it shows.
    if (find.byType(AlertDialog).evaluate().isNotEmpty) {
      await tester.tapAt(const Offset(4, 4)); // barrier
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    expect(s.favoriteGames, <String>['uno']);
    expect(s.onboarded, isTrue);
    expect(c.read(profileProvider).hasIdentity, isTrue);
    expect(find.text('HUB'), findsOneWidget);
  });
}
