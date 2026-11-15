import 'package:fl_clash/views/dashboard/fold.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(bool folded, double height, {bool animateIn = false}) =>
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: 300,
          child: DashboardFold(
            folded: folded,
            animateIn: animateIn,
            child: SizedBox(height: height),
          ),
        ),
      ),
    );

void main() {
  testWidgets('a tall card folds to the ordinary height and opens again', (
    tester,
  ) async {
    await tester.pumpWidget(_host(false, 600));
    expect(tester.getSize(find.byType(DashboardFold)).height, 600);

    await tester.pumpWidget(_host(true, 600));
    await tester.pump(const Duration(milliseconds: 100));
    final midway = tester.getSize(find.byType(DashboardFold)).height;
    expect(midway, lessThan(600));
    expect(midway, greaterThan(dashboardFoldedHeight));

    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(DashboardFold)).height,
      dashboardFoldedHeight,
    );

    await tester.pumpWidget(_host(false, 600));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(DashboardFold)).height, 600);
  });

  testWidgets('a short card keeps its height when folded', (tester) async {
    await tester.pumpWidget(_host(true, 120, animateIn: true));
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(DashboardFold)).height, 120);
  });
}
