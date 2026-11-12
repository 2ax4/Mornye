import 'package:flutter/material.dart';

/// A bubble that names the value a slider is being dragged to, pinned above
/// the thumb it follows.
///
/// The bubble renders through an [OverlayPortal] into the app's overlay, so
/// it floats above the surfaces that host the slider — the audio control
/// panel's glass and rounded clips would otherwise cut it in half. The
/// [LayerLink] keeps it attached to the slider while it shows, and
/// [progress] slides the bubble along the track with the thumb, the way the
/// sliders' own value indicator does.
class SliderValueBubble extends StatefulWidget {
  const SliderValueBubble({
    super.key,
    required this.visible,
    required this.label,
    required this.progress,
    required this.child,
  });

  /// Whether the gesture that names the value is running.
  final bool visible;

  /// The text the bubble shows, such as a percentage.
  final String label;

  /// Where the slider's thumb sits along its track, 0.0 to 1.0. The bubble
  /// parks above that point while it shows.
  final double progress;

  /// The slider (or slider row) the bubble floats above.
  final Widget child;

  @override
  State<SliderValueBubble> createState() => _SliderValueBubbleState();
}

class _SliderValueBubbleState extends State<SliderValueBubble> {
  final _link = LayerLink();
  final _portal = OverlayPortalController();

  bool get _visible => widget.visible && widget.label.isNotEmpty;

  @override
  void didUpdateWidget(SliderValueBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPortal();
  }

  void _syncPortal() {
    // OverlayPortal's show and hide must both run outside the build phase;
    // didUpdateWidget reaches here while the frame is still building.
    if (_visible && !_portal.isShowing) {
      // The root navigator's overlay is mounted long before a slider the
      // user can drag is on screen, and show() may not run during build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _visible && !_portal.isShowing) _portal.show();
      });
    } else if (!_visible && _portal.isShowing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_visible && _portal.isShowing) _portal.hide();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_visible && !_portal.isShowing) _syncPortal();
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: _buildBubble,
        child: widget.child,
      ),
    );
  }

  Widget _buildBubble(BuildContext overlayContext) {
    final colors = Theme.of(overlayContext).colorScheme;
    return Positioned.fill(
      child: Align(
        alignment: Alignment.topCenter,
        child: CompositedTransformFollower(
          link: _link,
          // The point above the thumb: the track's fraction the value names,
          // with a little margin so the bubble's nose never slides off the
          // slider's edge.
          targetAnchor: Alignment(
            (widget.progress.clamp(0.0, 1.0) * 2 - 1).clamp(-0.9, 0.9),
            -1,
          ),
          followerAnchor: Alignment.bottomCenter,
          offset: const Offset(0, -6),
          child: IgnorePointer(
            child: Material(
              color: colors.inverseSurface,
              borderRadius: BorderRadius.circular(999),
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Text(
                  widget.label,
                  style: Theme.of(overlayContext).textTheme.labelMedium
                      ?.copyWith(
                        color: colors.onInverseSurface,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
