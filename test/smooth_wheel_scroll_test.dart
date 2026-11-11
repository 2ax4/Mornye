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

    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    expect(position.pixels, greaterThan(0));
    expect(position.pixels, lessThan(100));

    await tester.pumpAndSettle();
    expect(position.pixels, 100);
    resetPlatform();
  });

  // The Library tab hosts its lists in a NestedScrollView: the coordinator
  // spends a downward wheel on the header first, and rewinds of the body's
  // share would be re-routed into the header while it can still move. The
  // body glides only once the header rests fully collapsed. The body list
  // stays controller-less: an own controller would detach it from the
  // coordinator's positions entirely.
  Widget buildNestedSurface(ScrollController outer) {
    debugDesktopPlatformOverride = true;
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    return MaterialApp(
      scrollBehavior: appScrollBehavior(
        disableOverscrollEffects: false,
        smoothScrolling: true,
      ),
      home: Scaffold(
        body: NestedScrollView(
          controller: outer,
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            const SliverAppBar(pinned: true, expandedHeight: 200),
          ],
          body: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
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
      ),
    );
  }

  testWidgets('header collapse keeps the native jump', (tester) async {
    final outer = ScrollController();
    addTearDown(outer.dispose);
    await tester.pumpWidget(buildNestedSurface(outer));
    await tester.pumpAndSettle();
    final inner = Scrollable.of(tester.element(find.text('row 2'))).position;

    tester.binding.handlePointerEvent(
      PointerScrollEvent(
        position: tester.getCenter(find.text('row 2')),
        scrollDelta: const Offset(0, 120),
      ),
    );
    await tester.pumpAndSettle();

    // NestedScrollView builds its outer scrollable without chrome, so no
    // wrapper guards the header: the notch lands natively and the body,
    // which received nothing, does not move.
    expect(outer.offset, 120);
    expect(inner.pixels, 0);
    resetPlatform();
  });

  testWidgets('a notch crossing the header glides only its body share', (
    tester,
  ) async {
    final outer = ScrollController();
    addTearDown(outer.dispose);
    await tester.pumpWidget(buildNestedSurface(outer));
    await tester.pumpAndSettle();
    final inner = Scrollable.of(tester.element(find.text('row 2'))).position;

    tester.binding.handlePointerEvent(
      PointerScrollEvent(
        position: tester.getCenter(find.text('row 2')),
        scrollDelta: const Offset(0, 400),
      ),
    );
    await tester.pump();
    // The header's share is spent natively at once (its scrollable carries
    // no wrapper); the body share, whose rewind would otherwise be
    // re-routed into the header, glides only once the header rests at its
    // maximum.
    expect(outer.offset, outer.position.maxScrollExtent);
    expect(inner.pixels, greaterThan(0));
    expect(inner.pixels, lessThan(400 - outer.offset));

    await tester.pumpAndSettle();
    expect(outer.offset, outer.position.maxScrollExtent);
    expect(inner.pixels, 400 - outer.offset);
    resetPlatform();
  });

  testWidgets('body glides and chains notches once the header is collapsed', (
    tester,
  ) async {
    final outer = ScrollController();
    addTearDown(outer.dispose);
    await tester.pumpWidget(buildNestedSurface(outer));
    await tester.pumpAndSettle();
    final inner = Scrollable.of(tester.element(find.text('row 2'))).position;

    // Collapse the header natively first; the event's body share glides.
    tester.binding.handlePointerEvent(
      PointerScrollEvent(
        position: tester.getCenter(find.text('row 2')),
        scrollDelta: const Offset(0, 400),
      ),
    );
    await tester.pumpAndSettle();
    final headerMax = outer.offset;
    expect(headerMax, outer.position.maxScrollExtent);
    final afterFirstNotch = inner.pixels;
    expect(afterFirstNotch, 400 - headerMax);

    // A notch over the body now glides: mid-flight the position left its
    // start but has not reached the native jump distance yet.
    tester.binding.handlePointerEvent(
      PointerScrollEvent(
        position: tester.getCenter(find.text('row 5')),
        scrollDelta: const Offset(0, 100),
      ),
    );
    await tester.pump();
    expect(inner.pixels, greaterThan(afterFirstNotch));
    expect(inner.pixels, lessThan(afterFirstNotch + 100));

    // A chained notch mid-glide accumulates into the same target.
    tester.binding.handlePointerEvent(
      PointerScrollEvent(
        position: tester.getCenter(find.text('row 6')),
        scrollDelta: const Offset(0, 100),
      ),
    );
    await tester.pumpAndSettle();
    expect(inner.pixels, afterFirstNotch + 200);
    expect(outer.offset, headerMax);
    resetPlatform();
  });
}
