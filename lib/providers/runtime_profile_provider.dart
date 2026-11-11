import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mornye/providers/settings_provider.dart';

/// True on low-end hardware (arm32-only or low-RAM, resolved at startup in
/// main.dart via a ProviderScope override). UI uses it to skip expensive
/// effects like the shell's backdrop blur.
final lowEndDeviceProvider = Provider<bool>((ref) => false);

/// Raw device capability decided by the startup runtime profile (overridden
/// in main.dart). Only the `high` tier enables blur by default.
final deviceSupportsBackdropBlurProvider = Provider<bool>((ref) => false);

/// Whether the GPU supports the higher blur budget and animated artwork /
/// lyric defocus. Glass controls themselves use the same lightweight renderer
/// on every tier. Overridden in main.dart.
final deviceSupportsLiquidGlassProvider = Provider<bool>((ref) => true);

/// Whether backdrop blur effects should render: the device default, or the
/// user's manual override from appearance settings.
final backdropBlurEnabledProvider = Provider<bool>((ref) {
  return ref.watch(deviceSupportsBackdropBlurProvider) ||
      ref.watch(settingsProvider.select((s) => s.forceBackdropBlur));
});

/// Flutter also reports Android's medium contrast as high contrast. Respect
/// that request unless the user explicitly forces glass; this only controls
/// decorative surfaces, never the inherited text or reduced-motion settings.
final mornyeGlassContrastBlockedProvider = Provider.family<bool, bool>(
  (ref, highContrast) =>
      highContrast &&
      !ref.watch(settingsProvider.select((s) => s.forceBackdropBlur)),
);

/// How much of Mornye's glass the device renders.
enum MornyeGlassLevel {
  /// Opaque surfaces; no backdrop sampling.
  flat,

  /// Translucent surfaces over one backdrop blur; no shader passes.
  frosted,

  /// Impeller backdrop refraction, with a blur fallback on other renderers.
  liquid,
}

final mornyeGlassLevelProvider = Provider<MornyeGlassLevel>((ref) {
  // A machine that needed too long for its first frame renders backdrops in
  // software; every blurred frame would stall it, so the session runs flat.
  if (!ref.watch(backdropBlurFeasibleProvider)) {
    return MornyeGlassLevel.flat;
  }
  final lowEnd = ref.watch(lowEndDeviceProvider);
  if (!lowEnd && ref.watch(deviceSupportsLiquidGlassProvider)) {
    return MornyeGlassLevel.liquid;
  }
  // The user's "always use blur effects" override restores the full material.
  if (ref.watch(backdropBlurEnabledProvider)) return MornyeGlassLevel.liquid;
  return lowEnd ? MornyeGlassLevel.flat : MornyeGlassLevel.frosted;
});

/// Backdrop blur for Mornye surfaces (frosted or liquid). Surfaces stay solid
/// until the first frame has rasterized: sampling the backdrop is the most
/// expensive pass a glass surface runs, and paying it on frame one is what
/// turned slow machines' launches into a long dark window.
final mornyeBlurEnabledProvider = Provider<bool>(
  (ref) =>
      ref.watch(mornyeGlassLevelProvider) != MornyeGlassLevel.flat &&
      ref.watch(firstFrameRenderedProvider),
);

/// Higher-quality glass and continuously filtered artwork / lyric effects.
final mornyeLiquidGlassProvider = Provider<bool>(
  (ref) => ref.watch(mornyeGlassLevelProvider) == MornyeGlassLevel.liquid,
);

/// Whether the liquid-glass backdrop pipeline has been rasterized once, so
/// surfaces may render the lens. Until then they fall back to the shared
/// frosted blur, keeping shader compilation off visible frames — without
/// this, switching styles or starting with glass freezes the window while
/// the pipeline compiles.
class MornyeGlassWarmupReady extends Notifier<bool> {
  MornyeGlassWarmupReady({this.initialValue = false});

  /// Tests and the detached warmup rasterizer seed `true` so the lens
  /// renders without running the preparation first.
  final bool initialValue;

  @override
  bool build() => initialValue;

  void markReady() => state = true;
}

final mornyeGlassWarmupReadyProvider =
    NotifierProvider<MornyeGlassWarmupReady, bool>(MornyeGlassWarmupReady.new);

/// Turns true once the first frame has rasterized. Glass surfaces watch it
/// before sampling the backdrop, so the launch frames paint solid tinted
/// panels and the blur passes only join once the window is already visible.
class FirstFrameRendered extends Notifier<bool> {
  FirstFrameRendered({this.initialValue = false});

  /// Tests seed `true` so surfaces render their filtering without waiting
  /// for a rasterized frame the test binding never produces.
  final bool initialValue;

  @override
  bool build() => initialValue;

  void markReady() => state = true;
}

final firstFrameRenderedProvider = NotifierProvider<FirstFrameRendered, bool>(
  FirstFrameRendered.new,
);

/// False for the rest of the session when the first frame rasterized so
/// slowly that the renderer is clearly running in software: every backdrop
/// sample would then stall each frame, and a solid launch beats a frozen
/// glass one.
class BackdropBlurFeasible extends Notifier<bool> {
  @override
  bool build() => true;

  void markInfeasible() => state = false;
}

final backdropBlurFeasibleProvider =
    NotifierProvider<BackdropBlurFeasible, bool>(BackdropBlurFeasible.new);
