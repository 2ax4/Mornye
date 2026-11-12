import 'package:flutter/material.dart';

/// A floating bubble that names the value a slider is being dragged to.
///
/// The bubble renders through an [OverlayPortal] into the app's overlay, so
/// it floats above the surfaces that host the slider — the audio control
/// panel's rounded clip and the glass would otherwise cut the bubble in
/// half. A [LayerLink] keeps it pinned above the slider while it shows.
class SliderValueBubble extends StatefulWidget {
  const SliderValueBubble({
    super.key,
    required this.visible,
    required this.label,
    required this.child,
  });

  /// Whether the gesture that names the value is running.
  final bool visible;

  /// The text the bubble shows, such as a percentage.
  final String label;

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
          targetAnchor: Alignment.topCenter,
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
