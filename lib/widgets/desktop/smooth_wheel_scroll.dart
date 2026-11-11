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
/// Every move — rewind and glide steps alike — goes through
/// [ScrollPosition.pointerScroll], the same clamped relative move the
/// framework's own wheel handler applies. On a NestedScrollView (the Library
/// tab) that routes through the coordinator, which spends a downward wheel
/// on the header before the body: a rewind of the body's share would be
/// re-routed into the header while it can still absorb it. So the wrapper
/// glides the body only once the header rests fully collapsed — it then
/// cannot absorb anything and every move lands on the body — while the
/// header's own collapse keeps the native jump, like any collapsing-toolbar
/// app.
///
/// The chrome builds INSIDE the Scrollable element but ABOVE its
/// _ScrollableScope, so inherited lookups return null here and a downward
/// walk only reaches nested shelves inside the content. Instead the position
/// is resolved at wheel time by walking UP to the owning ScrollableState,
/// which works with and without page-provided controllers. Events the owner
/// did not act on (a nested shelf consumed them, the list is at an edge, or
/// the surface scrolls horizontally) keep their native behavior.
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

  /// An outer NestedScrollView position tolerates half a pixel of rounding
  /// before the body is considered to have the wheel to itself.
  static const _headerSettledEpsilon = 0.5;

  Ticker? _ticker;
  ScrollPosition? _position;
  double? _target;

  void _cancel() {
    _ticker?.stop();
    _target = null;
    _position = null;
  }

  void _onPointerDown(PointerDownEvent event) => _cancel();

  /// Walks up from the chrome to the ScrollableState that owns this
  /// wrapper. The chrome sits between the Scrollable element and its
  /// _ScrollableScope, so the owner is always the first ScrollableState
  /// ancestor; walking down would only find nested shelves in the content.
  /// Visiting elements is only allowed outside build, so this runs in the
  /// pointer-signal handler, never during layout.
  ScrollPosition? _findPosition() {
    ScrollPosition? position;
    try {
      context.visitAncestorElements((element) {
        if (element is StatefulElement && element.state is ScrollableState) {
          try {
            position = (element.state as ScrollableState).position;
          } catch (_) {
            // A ScrollableState mid-disposal has no position; scrolling is
            // best effort and must never break input handling.
          }
          return false;
        }
        return true;
      });
    } catch (_) {
      return null;
    }
    return position;
  }

  /// Whether [position] may glide where it sits. Inside a NestedScrollView
  /// only the body glides, and only once its header is fully collapsed; see
  /// the class documentation for the coordinator routing behind this.
  bool _mayGlide(ScrollPosition position) {
    final NestedScrollViewState? nested;
    try {
      nested = context.findAncestorStateOfType<NestedScrollViewState>();
    } catch (_) {
      return false;
    }
    if (nested == null) return true;
    final outerController = nested.outerController;
    if (!outerController.hasClients) return false;
    final outer = outerController.position;
    if (!outer.hasContentDimensions) return false;
    // With the header at its maximum it cannot absorb another pixel, so the
    // rewind and every glide step land on the body exactly.
    return outer.pixels >= outer.maxScrollExtent - _headerSettledEpsilon;
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
        if (!_mayGlide(position)) return;
        // Undo the native jump before this frame is painted; the glide below
        // covers the same distance smoothly. pointerScroll clamps to the
        // position's own extents, which restores `before` exactly because
        // the native jump started there.
        position.pointerScroll(-delta);
        var target = (_target ?? before) + delta;
        if (target < position.minScrollExtent) {
          target = position.minScrollExtent;
        } else if (target > position.maxScrollExtent) {
          target = position.maxScrollExtent;
        }
        _target = target;
        _position = position;
        // A chained notch arrives while the glide is still running: start()
        // on an active ticker would throw and silently kill the glide.
        final ticker = _ticker ??= createTicker(_onTick);
        if (!ticker.isActive) ticker.start();
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
    // to it instead of fighting the user's own motion. Our own pointerScroll
    // steps end idle under the desktop clamping physics, so this only fires
    // for someone else's gesture.
    if (position.isScrollingNotifier.value) {
      _cancel();
      return;
    }
    final current = position.pixels;
    final diff = target - current;
    if (diff.abs() <= _snapThreshold) {
      try {
        if (diff != 0) position.pointerScroll(diff);
      } catch (_) {
        // The position may be disposing between frames.
      }
      _cancel();
      return;
    }
    var step = diff * _smoothing;
    if (step.abs() > _maxStepPerFrame) {
      step = step.isNegative ? -_maxStepPerFrame : _maxStepPerFrame;
    }
    try {
      position.pointerScroll(step);
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
