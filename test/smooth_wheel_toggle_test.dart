import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mornye/app.dart';
import 'package:mornye/utils/desktop_platform.dart';
import 'package:mornye/widgets/desktop/smooth_wheel_scroll.dart';

void main() {
  void resetPlatform() {
    debugDesktopPlatformOverride = null;
    debugDefaultTargetPlatformOverride = null;
  }

  Widget surface(bool smooth) {
    debugDesktopPlatformOverride = true;
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    return MaterialApp(
      scrollBehavior: appScrollBehavior(
        disableOverscrollEffects: false,
        smoothScrolling: smooth,
      ),
      home: Scaffold(
        body: ListView.builder(
          itemExtent: 80,
          itemCount: 60,
          itemBuilder: (context, index) => Text('item $index'),
        ),
      ),
    );
  }

  Future<double> wheelOnce(WidgetTester tester) async {
    tester.binding.handlePointerEvent(
      PointerScrollEvent(
        position: tester.getCenter(find.text('item 3')),
        scrollDelta: const Offset(0, 100),
      ),
    );
    await tester.pump();
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    final midFlight = position.pixels;
    await tester.pumpAndSettle();
    return midFlight;
  }

  testWidgets('turning smooth scrolling off updates a live list', (
    tester,
  ) async {
    await tester.pumpWidget(surface(true));
    await tester.pumpAndSettle();
    expect(find.byType(SmoothWheelScroll), findsOneWidget);

    // The user flips the toggle; the app rebuilds with smoothScrolling: false
    // while the list stays mounted.
    await tester.pumpWidget(surface(false));
    await tester.pumpAndSettle();
    expect(find.byType(SmoothWheelScroll), findsNothing);

    final midFlight = await wheelOnce(tester);
    expect(midFlight, 100);
    resetPlatform();
  });

  testWidgets('turning smooth scrolling on updates a live list', (
    tester,
  ) async {
    await tester.pumpWidget(surface(false));
    await tester.pumpAndSettle();
    expect(find.byType(SmoothWheelScroll), findsNothing);

    await tester.pumpWidget(surface(true));
    await tester.pumpAndSettle();
    expect(find.byType(SmoothWheelScroll), findsOneWidget);

    final midFlight = await wheelOnce(tester);
    expect(midFlight, lessThan(100));
    expect(midFlight, greaterThan(0));
    resetPlatform();
  });
}
