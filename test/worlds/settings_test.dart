import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/settings/app_settings.dart';
import 'package:nexora/core/storage/local_store.dart';
import 'package:nexora/core/theme/nx_theme.dart';
import 'package:nexora/core/ui2/nx2_widgets.dart';
import 'package:nexora/worlds/settings/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mirrors NexoraApp's theme wiring: theme built from the settings, static tokens flipped, live on change.
class _App extends ConsumerWidget {
  const _App();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppSettings s = ref.watch(settingsProvider);
    final bool light = s.isLight(Brightness.dark);
    NxColors.light = light;
    Nx2.light = light;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildNxTheme(light: light, highContrast: s.highContrast),
      locale: const Locale('en'),
      supportedLocales: const <Locale>[Locale('fa'), Locale('en')],
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const SettingsPage(),
    );
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{'settings.lang': 'en'});
    await LocalStore.init();
  });
  tearDown(() {
    NxColors.light = false;
    Nx2.light = false;
  });

  test('new settings have safe defaults, persist and clamp', () {
    final AppSettings s = AppSettings(LocalStore.instance);
    expect(s.themeMode, ThemeMode.dark);
    expect(s.notifyInvites, isTrue);
    expect(s.notifyTournaments, isTrue);
    expect(s.oracleOffline, isFalse);
    expect(s.highContrast, isFalse);
    expect(s.fontScale, 1.0);

    s.themeMode = ThemeMode.system;
    expect(s.isLight(Brightness.light), isTrue);
    expect(s.isLight(Brightness.dark), isFalse);
    s.themeMode = ThemeMode.light;
    expect(s.isLight(Brightness.dark), isTrue);
    s.fontScale = 9;
    expect(s.fontScale, AppSettings.maxFontScale);
    s.notifyInvites = false;
    s.oracleOffline = true;

    final AppSettings again = AppSettings(LocalStore.instance);
    expect(again.themeMode, ThemeMode.light);
    expect(again.fontScale, AppSettings.maxFontScale);
    expect(again.notifyInvites, isFalse);
    expect(again.oracleOffline, isTrue);
  });

  testWidgets('one grouped settings page; theme switches live; toggles are wired', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final ProviderContainer c = ProviderContainer();
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const _App()));
    await tester.pump(const Duration(milliseconds: 500));
    final AppSettings s = c.read(settingsProvider);
    final Finder list = find.descendant(
        of: find.byKey(const Key('settings.list')), matching: find.byType(Scrollable)).first;
    Future<void> reveal(Key k, double dir) async {
      await tester.scrollUntilVisible(find.byKey(k), dir, scrollable: list);
      await tester.pump();
      await Scrollable.ensureVisible(tester.element(find.byKey(k)), alignment: 0.5);
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Every group exists, once.
    for (final String section in <String>[
      'Account',
      'Notifications',
      'Privacy & data',
      'Language',
      'Theme & graphics',
      'Sound & haptics',
      'Accessibility',
      'ORACLE',
    ]) {
      await tester.scrollUntilVisible(find.text(section), 200, scrollable: list);
      expect(find.text(section), findsOneWidget, reason: section);
    }

    // Theme: dark by default, Light switches the live theme.
    await reveal(const Key('settings.theme.light'), -200);
    BuildContext ctx() => tester.element(find.byKey(const Key('settings.list')));
    expect(Theme.of(ctx()).brightness, Brightness.dark);
    await tester.tap(find.byKey(const Key('settings.theme.light')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(s.themeMode, ThemeMode.light);
    expect(Theme.of(ctx()).brightness, Brightness.light);
    expect(Nx2.light, isTrue);
    await tester.tap(find.byKey(const Key('settings.theme.dark')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(Theme.of(ctx()).brightness, Brightness.dark);

    // Notifications are wired to the settings the watchers read.
    await reveal(const Key('settings.notify_invites'), -200);
    await tester.tap(find.byKey(const Key('settings.notify_invites')));
    await tester.pump();
    expect(s.notifyInvites, isFalse);
    await tester.tap(find.byKey(const Key('settings.notify_tournaments')));
    await tester.pump();
    expect(s.notifyTournaments, isFalse);

    // Accessibility + ORACLE.
    await reveal(const Key('settings.high_contrast'), 200);
    await tester.tap(find.byKey(const Key('settings.high_contrast')));
    await tester.pump();
    expect(s.highContrast, isTrue);
    await reveal(const Key('settings.oracle_offline'), 200);
    await tester.tap(find.byKey(const Key('settings.oracle_offline')));
    await tester.pump();
    expect(s.oracleOffline, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
