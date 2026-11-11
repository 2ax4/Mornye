import 'dart:async';

import 'package:flutter/gestures.dart'
    show PointerScrollEvent, PointerSignalEvent;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Animates mouse wheel scrolling on desktop instead of the default instant
/// jump per wheel notch.
///
/// Wheel steps accumulate into a target offset and the position approaches
/// that target every frame — 20% of the remaining distance per frame, capped
/// at 80 logical pixels — so chained notches glide together instead of
/// restarting a short animation on every event. The native jump is rewound
/// in the same frame it arrives, so only the glide is ever visible. Nested
/// scrollables keep their native behavior, because only a scrollable that
/// actually moved is animated.
class SmoothWheelScroll extends StatefulWidget {
  const SmoothWheelScroll({super.key, required this.child});

  final Widget child;

  @override
  State<SmoothWheelScroll> createState() => _SmoothWheelScrollState();
}

class _SmoothWheelScrollState extends State<SmoothWheelScroll>
    with SingleTickerProviderStateMixin {
  // The reference Windows smooth-scroll constants: per frame 20% of the
  // remaining distance, at most 80 logical pixels, snapping inside half a
  // pixel of the target.
  static const _smoothing = 0.20;
  static const _maxStepPerFrame = 80.0;
  static const _snapThreshold = 0.5;

  Ticker? _ticker;
  ScrollPosition? _position;
  double? _target;

  void _cancel() {
    _ticker?.stop();
    _target = null;
    _position = null;
  }

  void _onPointerDown(PointerDownEvent event) => _cancel();

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
    // handler has applied its clamped jump (or not moved at all, which means
    // the event was handled by a nested scrollable, blocked, or already at an
    // edge) and this wrapper only animates the movement it observes.
    scheduleMicrotask(() {
      try {
        if (!position.hasContentDimensions) return;
        final delta = position.pixels - before;
        if (delta == 0) return;
        // Undo the native jump before this frame is painted; the glide below
        // covers the same distance smoothly.
        position.jumpTo(before);
        var target = (_target ?? before) + delta;
        if (target < position.minScrollExtent) {
          target = position.minScrollExtent;
        } else if (target > position.maxScrollExtent) {
          target = position.maxScrollExtent;
        }
        _target = target;
        _position = position;
        (_ticker ??= createTicker(_onTick)).start();
      } catch (_) {
        // The position may be disposing between frames; scrolling is best
        // effort and must never break input handling.
      }
    });
  }

  void _onTick(Duration elapsed) {
    final position = _position;
    final target = _target;
    if (position == null ||
        target == null ||
        !position.hasContentDimensions) {
      _cancel();
      return;
    }
    // A drag, scrollbar pull or trackpad pan took over the position: yield
    // to it instead of fighting the user's own motion.
    if (position.isScrollingNotifier.value) {
      _cancel();
      return;
    }
    final current = position.pixels;
    final diff = target - current;
    if (diff.abs() <= _snapThreshold) {
      position.jumpTo(target);
      _cancel();
      return;
    }
    var step = diff * _smoothing;
    if (step.abs() > _maxStepPerFrame) {
      step = step.isNegative ? -_maxStepPerFrame : _maxStepPerFrame;
    }
    try {
      position.jumpTo(current + step);
    } catch (_) {
      // The position may be disposing between frames; scrolling is best
      // effort and must never break input handling.
      _cancel();
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerSignal: _onPointerSignal,
    onPointerDown: _onPointerDown,
    child: widget.child,
  );
}
