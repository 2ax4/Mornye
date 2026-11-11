import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mornye/app.dart';
import 'package:mornye/utils/desktop_platform.dart';

void main() {
  void resetPlatform() {
    debugDesktopPlatformOverride = null;
    debugDefaultTargetPlatformOverride = null;
  }

  // The chrome that hosts the glide wrapper is built INSIDE the Scrollable
  // element, so the wrapper must reach its own scrollable by walking UP.
  // These tests guard the lookup against the two surfaces that regressed:
  // the home-style list with a nested shelf, and controller-less lists.
  Widget buildHomeLikeSurface(ScrollController main, ScrollController shelf) {
    debugDesktopPlatformOverride = true;
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    return MaterialApp(
      scrollBehavior: appScrollBehavior(
        disableOverscrollEffects: false,
        smoothScrolling: true,
      ),
      home: Scaffold(
        body: CustomScrollView(
          controller: main,
          slivers: [
            SliverToBoxAdapter(
              child: SizedBox(
                height: 120,
                child: ListView.builder(
                  controller: shelf,
                  scrollDirection: Axis.horizontal,
                  itemExtent: 200,
                  itemCount: 30,
                  itemBuilder: (context, index) =>
                      ColoredBox(color: Colors.primaries[index % 18]),
                ),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) =>
                    SizedBox(height: 80, child: Text('row $index')),
                childCount: 60,
              ),
            ),
          ],
        ),
      ),
    );
  }

  testWidgets('wheel over a plain row glides the main list, not a shelf', (
    tester,
  ) async {
    final main = ScrollController();
    final shelf = ScrollController();
    addTearDown(main.dispose);
    addTearDown(shelf.dispose);
    await tester.pumpWidget(buildHomeLikeSurface(main, shelf));
    await tester.pumpAndSettle();
    expect(main.offset, 0);

    // Aim below the shelf, over a plain row: the main list is the scrollable
    // the wheel acts on.
    tester.binding.handlePointerEvent(
      PointerScrollEvent(
        position: tester.getCenter(find.text('row 2')),
        scrollDelta: const Offset(0, 100),
      ),
    );
    await tester.pump();

    // The native jump was rewound and the glide is mid-flight: the position
    // left its start but has not reached the jump target yet.
    expect(shelf.offset, 0);
    expect(main.offset, greaterThan(0));
    expect(main.offset, lessThan(100));

    await tester.pumpAndSettle();
    expect(main.offset, 100);
    expect(shelf.offset, 0);
    resetPlatform();
  });

  testWidgets('lists without a controller glide too', (tester) async {
    debugDesktopPlatformOverride = true;
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: appScrollBehavior(
          disableOverscrollEffects: false,
          smoothScrolling: true,
        ),
        home: Scaffold(
          body: ListView.builder(
            itemExtent: 80,
            itemCount: 60,
            itemBuilder: (context, index) => Text('item $index'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    tester.binding.handlePointerEvent(
      PointerScrollEvent(
        position: tester.getCenter(find.text('item 3')),
        scrollDelta: const Offset(0, 100),
      ),
    );
    await tester.pump();

    final position = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    ).position;
    expect(position.pixels, greaterThan(0));
    expect(position.pixels, lessThan(100));

    await tester.pumpAndSettle();
    expect(position.pixels, 100);
    resetPlatform();
  });
}
