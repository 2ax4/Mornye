import 'dart:async';

import 'package:flutter/gestures.dart'
    show PointerScrollEvent, PointerSignalEvent;
import 'package:flutter/widgets.dart';

/// Animates mouse wheel scrolling on desktop instead of the default instant
/// jump per wheel notch.
///
/// Flutter handles a wheel tick by jumping the scroll position in one frame.
/// This wrapper sits around the scrollable's chrome and, after the native
/// handler has applied its clamped jump, rewinds to the position the pointer
/// saw and animates to the same target, so the user only ever sees a short
/// ease-out glide. Events over nested scrollables keep their own native
/// behavior, because only the nearest scrollable is rewound when it moved.
class SmoothWheelScroll extends StatefulWidget {
  const SmoothWheelScroll({super.key, required this.child});

  final Widget child;

  @override
  State<SmoothWheelScroll> createState() => _SmoothWheelScrollState();
}

class _SmoothWheelScrollState extends State<SmoothWheelScroll> {
  static const _duration = Duration(milliseconds: 150);

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || event.scrollDelta.dy == 0) return;
    final scrollable = Scrollable.maybeOf(context);
    if (scrollable == null) return;
    // Horizontal shelves have their own scroll arrows; leave them native.
    if (axisDirectionToAxis(scrollable.widget.axisDirection) != Axis.vertical) {
      return;
    }
    if (MediaQuery.disableAnimationsOf(context)) return;
    final position = scrollable.position;
    if (!position.hasContentDimensions) return;
    final before = position.pixels;
    // Runs after the whole pointer-signal dispatch: by then the native
    // handler has applied its jump (or not moved at all, which means the
    // event was handled by a nested scrollable, blocked, or already at an
    // edge) and this wrapper only animates the movement it observes.
    scheduleMicrotask(() {
      try {
        if (!position.hasContentDimensions) return;
        final target = position.pixels;
        if (target == before) return;
        position.jumpTo(before);
        position.animateTo(
          target,
          duration: _duration,
          curve: Curves.easeOutCubic,
        );
      } catch (_) {
        // The position may be disposing between frames; scrolling is best
        // effort and must never break input handling.
      }
    });
  }

  @override
  Widget build(BuildContext context) =>
      Listener(onPointerSignal: _onPointerSignal, child: widget.child);
}
