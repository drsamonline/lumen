import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/ui/support_dialog.dart';

void main() {
  Future<void> pumpDialog(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SupportDialog())),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows all six handles at phone width without overflowing', (
    tester,
  ) async {
    await pumpDialog(tester, const Size(360, 780));

    expect(tester.takeException(), isNull);
    expect(find.text('drsohilboi@ybl'), findsOneWidget);
    expect(find.textContaining('ko-fi.com/matneo'), findsOneWidget);
    expect(find.textContaining('paypal.me/drsohilmomin'), findsOneWidget);
    expect(find.textContaining('B08ZT331LY'), findsOneWidget);
    expect(find.textContaining('drsamonline.github.io'), findsOneWidget);
    expect(find.text('sohilmomin2000@gmail.com'), findsOneWidget);
  });

  testWidgets('survives a narrow window', (tester) async {
    await pumpDialog(tester, const Size(320, 640));
    expect(tester.takeException(), isNull);
  });

  testWidgets('says nothing is gated', (tester) async {
    await pumpDialog(tester, const Size(360, 780));
    expect(find.textContaining('Nothing in the app'), findsOneWidget);
  });
}
