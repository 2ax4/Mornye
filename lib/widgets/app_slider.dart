import 'package:flutter/material.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:mornye/theme/material_expressive.dart';

const Color _transparent = Color(0x00000000);

/// Settings slider with the Material 3 Expressive track and handle.
/// Mornye and reduced motion keep the standard [Slider].
class AppSlider extends StatelessWidget {
  const AppSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.label,
    this.semanticFormatterCallback,
    this.trackThickness,
    this.thumbLength,
    this.centered = false,
    this.vertical = false,
    this.semanticLabel,
    this.showValueIndicator = true,
  });

  final double value;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;
  final double min;
  final double max;
  final int? divisions;
  final String? label;
  final SemanticFormatterCallback? semanticFormatterCallback;

  /// Expressive track height; a secondary control can sit thinner than the
  /// default extra-small track.
  final double? trackThickness;

  /// Expressive handle height; shorten it together with a thinner track so
  /// the handle stays in proportion.
  final double? thumbLength;

  /// Grows the active track from the middle of the range, for bipolar values
  /// such as gain or balance.
  final bool centered;

  /// Lays the slider out bottom (min) to top (max).
  final bool vertical;

  /// What the slider adjusts, read before its value; [label] only names the
  /// value bubble.
  final String? semanticLabel;

  /// Whether the expressive slider raises its own value indicator while the
  /// handle is held. A slider that names its value some other way — the
  /// volume slider's floating percentage bubble — turns it off, or the
  /// value would show twice.
  final bool showValueIndicator;

  @override
  Widget build(BuildContext context) {
    final slider = _buildSlider(context);
    if (semanticLabel == null) return slider;
    return MergeSemantics(
      child: Semantics(label: semanticLabel, child: slider),
    );
  }

  Widget _buildSlider(BuildContext context) {
    if (!materialExpressiveEnabled(context)) {
      final slider = Slider(
        value: value,
        min: min,
        max: max,
        divisions: divisions,
        label: label,
        semanticFormatterCallback: semanticFormatterCallback,
        onChanged: onChanged,
        onChangeEnd: onChangeEnd,
      );
      return vertical ? RotatedBox(quarterTurns: 3, child: slider) : slider;
    }
    final enabled = onChanged != null;
    Widget expressive(Widget widget) => MaterialExpressiveScope(
      child: showValueIndicator
          ? widget
          : // The expressive slider paints its indicator in the inverse
            // roles with no switch to turn it off; an expressive theme whose
            // inverse roles are transparent hides it for this slider alone.
            Builder(
              builder: (context) {
                final theme = M3ETheme.of(context);
                final scheme = theme.colorScheme.copyWith(
                  inverseSurface: _transparent,
                  onInverseSurface: _transparent,
                );
                return M3ETheme(
                  data: theme.copyWith(colorScheme: scheme),
                  child: widget,
                );
              },
            ),
    );
    final slider = expressive(switch ((vertical, centered)) {
      (true, true) => M3ESlider.verticalCentered(
        value: value,
        min: min,
        max: max,
        divisions: divisions,
        label: label,
        semanticFormatterCallback: semanticFormatterCallback,
        trackThickness: trackThickness,
        thumbLength: thumbLength,
        enabled: enabled,
        onChanged: onChanged,
        onChangeEnd: onChangeEnd,
      ),
      (true, false) => M3ESlider.vertical(
        value: value,
        min: min,
        max: max,
        divisions: divisions,
        label: label,
        semanticFormatterCallback: semanticFormatterCallback,
        trackThickness: trackThickness,
        thumbLength: thumbLength,
        enabled: enabled,
        onChanged: onChanged,
        onChangeEnd: onChangeEnd,
      ),
      (false, true) => M3ESlider.centered(
        value: value,
        min: min,
        max: max,
        divisions: divisions,
        label: label,
        semanticFormatterCallback: semanticFormatterCallback,
        trackThickness: trackThickness,
        thumbLength: thumbLength,
        enabled: enabled,
        onChanged: onChanged,
        onChangeEnd: onChangeEnd,
      ),
      (false, false) => M3ESlider(
        value: value,
        min: min,
        max: max,
        divisions: divisions,
        label: label,
        semanticFormatterCallback: semanticFormatterCallback,
        trackThickness: trackThickness,
        thumbLength: thumbLength,
        enabled: enabled,
        onChanged: onChanged,
        onChangeEnd: onChangeEnd,
      ),
    });
    // The expressive slider lays out 44 dp across; stretch it to the 48 dp
    // touch target the standard Slider already has.
    return vertical
        ? ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48),
            child: slider,
          )
        : SizedBox(height: 48, child: slider);
  }
}
