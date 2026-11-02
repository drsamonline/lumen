import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/ui/widgets/month_header.dart';

void main() {
  Widget scroll(MonthHeaderDelegate header) {
    return MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: <Widget>[
            SliverPersistentHeader(pinned: true, delegate: header),
            const SliverToBoxAdapter(child: SizedBox(height: 2000)),
          ],
        ),
      ),
    );
  }

  testWidgets('renders the label and the count', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      scroll(MonthHeaderDelegate(
        label: 'November 2026',
        count: 131,
        background: const Color(0xFF101214),
        divider: const Color(0xFF333333),
      )),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('November 2026'), findsOneWidget);
    expect(find.text('131'), findsOneWidget);
  });

  testWidgets('stays pinned while the group scrolls past', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      scroll(MonthHeaderDelegate(
        label: 'November 2026',
        count: 12,
        background: const Color(0xFF101214),
        divider: const Color(0xFF333333),
      )),
    );

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();

    // Pinned: still on screen after scrolling its group away.
    expect(find.text('November 2026'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a very long month name does not overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      scroll(MonthHeaderDelegate(
        label: 'September 2026 — a very long label indeed',
        count: 12345,
        background: const Color(0xFF101214),
        divider: const Color(0xFF333333),
      )),
    );

    expect(tester.takeException(), isNull);
  });
}
