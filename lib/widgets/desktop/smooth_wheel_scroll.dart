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
/// in the same frame it arrives, so only the glide is ever visible.
///
/// The chrome builds OUTSIDE the scrollable's scope, so inherited lookups
/// return null here. Instead the position is resolved at wheel time by
/// walking down to the nearest scrollable, which works with and without
/// page-provided controllers. Events the nearest scrollable did not act on
/// (a nested shelf consumed them, the list is at an edge, or the surface
/// scrolls horizontally) keep their native behavior.
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

  /// Walks down from the chrome to the scrollable the wheel event will act
  /// on. Visiting elements is only allowed outside build, so this runs in
  /// the pointer-signal handler, never during layout.
  ScrollPosition? _findPosition() {
    ScrollableState? scrollable;
    void visit(Element element) {
      if (scrollable != null) return;
      if (element is StatefulElement && element.state is ScrollableState) {
        scrollable = element.state as ScrollableState;
        return;
      }
      element.visitChildElements(visit);
    }

    try {
      context.visitChildElements(visit);
    } catch (_) {
      return null;
    }
    try {
      return scrollable?.position;
    } catch (_) {
      return null;
    }
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || event.scrollDelta.dy == 0) return;
    if (MediaQuery.disableAnimationsOf(context)) return;
    final position = _findPosition();
    if (position == null || !position.hasContentDimensions) return;
    final before = position.pixels;
    // Runs after the whole pointer-signal dispatch: by then the native
    // handler has applied its clamped jump (or not moved at all, which means
    // the event was handled by a nested scrollable, blocked, or already at an
    // edge) and this wrapper only animates the movement it observes.
    scheduleMicrotask(() {
      try {
        if (!position.hasContentDimensions) return;
        final delta = position.pixels - before;
        // A nested shelf or an edge consumed the event, or the surface
        // scrolls horizontally with its own arrows: leave it native.
        if (delta == 0 ||
            axisDirectionToAxis(position.axisDirection) != Axis.vertical) {
          return;
        }
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
        _cancel();
      }
    });
  }

  void _onTick(Duration elapsed) {
    final position = _position;
    final target = _target;
    if (position == null || target == null || !position.hasContentDimensions) {
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
