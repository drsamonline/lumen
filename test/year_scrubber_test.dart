import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumen/ui/widgets/year_scrubber.dart';

List<ScrubMarker> years(int count) => <ScrubMarker>[
      for (var i = 0; i < count; i++)
        ScrubMarker(year: 2024 - i, offset: i * 1000.0),
    ];

void main() {
  Widget host(Widget child, {Size size = const Size(360, 640)}) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: Scaffold(body: Row(children: <Widget>[const Spacer(), child])),
      ),
    );
  }

  testWidgets('a three-year library shows every year', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      host(YearScrubber(markers: years(3), onSeek: (_) {})),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('2024'), findsOneWidget);
    expect(find.text('2022'), findsOneWidget);
  });

  testWidgets('thirty years are thinned instead of overflowing', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      host(YearScrubber(markers: years(30), onSeek: (_) {})),
    );

    // A RenderFlex overflow throws, so this is the regression guard.
    expect(tester.takeException(), isNull);
    // Every marker would be 30 labels; the rail must show fewer.
    final labels = find.byType(Text).evaluate().length;
    expect(labels, lessThan(30));
    expect(labels, greaterThan(1));
    // The newest year is the one people reach for, so it survives thinning.
    expect(find.text('2024'), findsOneWidget);
  });

  testWidgets('a short window still lays out', (tester) async {
    tester.view.physicalSize = const Size(360, 160);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      host(YearScrubber(markers: years(30), onSeek: (_) {}), size: const Size(360, 160)),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping the rail seeks', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    double? sought;
    await tester.pumpWidget(
      host(YearScrubber(markers: years(3), onSeek: (offset) => sought = offset)),
    );

    await tester.tapAt(tester.getCenter(find.byType(YearScrubber)));
    await tester.pumpAndSettle();

    expect(sought, isNotNull);
    expect(<double>[0, 1000, 2000], contains(sought));
  });
}
