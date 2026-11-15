import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/screens/auth_start.dart';

void main() {
  testWidgets('welcome gate offers account, guest, and offline paths', (tester) async {
    var continued = false;
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: AuthStartScreen(onContinue: () => continued = true)));
    await tester.pumpAndSettle();

    expect(find.text('به جهان نکسورا خوش آمدی'), findsOneWidget);
    expect(find.text('ثبت‌نام'), findsOneWidget);
    expect(find.text('ادامه به‌عنوان مهمان'), findsOneWidget);
    expect(find.text('فعلاً بدون حساب ادامه بده'), findsOneWidget);

    await tester.ensureVisible(find.text('فعلاً بدون حساب ادامه بده'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('فعلاً بدون حساب ادامه بده'));
    expect(continued, isTrue);
  });
}
