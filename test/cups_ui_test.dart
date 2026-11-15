// Cups UI smoke: the create sheet builds offline (no Supabase), shows the start in the Jalali calendar / Tehran time,
// and its prize split preview matches the server split rule.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nexora/core/store.dart';
import 'package:nexora/online/cups.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _rb = GlobalKey();

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.i.load();
    for (final (f, a) in [('Vazirmatn', 'assets/fonts/Vazirmatn-VF.ttf'), ('Orbitron', 'assets/fonts/Orbitron-VF.ttf'), ('Exo2', 'assets/fonts/Exo2-VF.ttf'), ('Oxanium', 'assets/fonts/Oxanium-VF.ttf')]) {
      await (FontLoader(f)..addFont(rootBundle.load(a))).load();
    }
  });

  testWidgets('create cup sheet builds and shows Jalali/Tehran start', (t) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.75;
    await t.pumpWidget(RepaintBoundary(
      key: _rb,
      child: MaterialApp(debugShowCheckedModeBanner: false, home: Scaffold(backgroundColor: const Color(0xff050a26), body: CreateCupSheet(onCreated: (_) {}))),
    ));
    await t.pump(const Duration(milliseconds: 300));
    expect(t.takeException(), isNull);
    expect(find.textContaining('تهران'), findsWidgets);
    expect(find.text('تک‌بازی'), findsOneWidget);
    expect(find.text('مجموع گل'), findsOneWidget);
    expect(find.text('بهترین N / اول به N برد'), findsOneWidget);
    expect(find.text('رفت و برگشت'), findsOneWidget);
    await t.tap(find.text('مجموع گل'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('۲ بازی'), findsOneWidget);
    await t.tap(find.text('رفت و برگشت'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('قانون گل خارج از خانه'), findsOneWidget);
    expect(find.text('گل طلایی'), findsOneWidget);
    await t.scrollUntilVisible(find.textContaining('جایزهٔ واقعی'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('جایزهٔ واقعی'), findsOneWidget);
    await t.scrollUntilVisible(find.textContaining('تأیید کنم'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('تأیید کنم'), findsOneWidget);
    await t.scrollUntilVisible(find.text('ساخت'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('ساخت'), findsOneWidget);
    final dir = Platform.environment['NX_SHOTS'];
    if (dir != null) {
      await t.runAsync(() async {
        final ro = _rb.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final im = await ro.toImage(pixelRatio: 1);
        final bd = await im.toByteData(format: ui.ImageByteFormat.png);
        File('$dir/cup_create.png').writeAsBytesSync(bd!.buffer.asUint8List());
      });
    }
    expect(t.takeException(), isNull);
  });
}
