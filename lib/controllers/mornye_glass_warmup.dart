import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:mornye/providers/runtime_profile_provider.dart';
import 'package:mornye/theme/mornye_theme.dart';
import 'package:mornye/widgets/mornye_chrome.dart';
import 'package:mornye/utils/logger.dart';

/// Prepares the actual backdrop pipeline, not just the fragment asset. The
/// detached scene is rasterized once and discarded without presenting a frame.
class MornyeGlassWarmup {
  static Future<void>? _pending;
  static bool _ready = false;
  static final _log = AppLogger('MornyeGlass');

  @visibleForTesting
  static bool get isReady => _ready;

  static Future<void> prepare(ui.FlutterView view) {
    if (!ui.ImageFilter.isShaderFilterSupported) return Future<void>.value();
    return _pending ??= _prepare(view).catchError((Object error) {
      // Preparation is optional; keep the package's existing lazy fallback.
      _log.w('Glass preparation failed: $error');
    });
  }

  static Future<void> _prepare(ui.FlutterView view) async {
    // GLES needs the view's initialized graphics context. A first-frame
    // callback only means painting was submitted, not that rasterization ran.
    await Future.wait<void>([
      LiquidGlassShaders.ensureLoaded(),
      WidgetsBinding.instance.waitUntilFirstFrameRasterized,
    ]);
    // Compiling the lens pipeline stalls the raster thread for a while.
    // Starting straight after the first frame turned the whole launch into a
    // long white or frozen window, so let the shell settle first: a floor
    // past startup, then a frame-free moment before the rasterization.
    await Future<void>.delayed(const Duration(seconds: 2));
    await _waitForFrameQuiet(30);
    // Do not compete with an entrance, theme switch or scrolling animation.
    await SchedulerBinding.instance.scheduleTask(
      () async {
        final binding = WidgetsBinding.instance;
        if (binding.lifecycleState != AppLifecycleState.resumed ||
            !binding.platformDispatcher.views.contains(view)) {
          _pending = null;
          return;
        }
        await _rasterize(view);
        _ready = true;
      },
      Priority.idle,
      debugLabel: 'Prepare Mornye glass backdrop',
    );
  }

  /// Waits through at most [maxAttempts] 100 ms gaps for a moment without a
  /// scheduled frame or a running animation, so one-off heavy work does not
  /// land mid-motion. A busy UI never goes perfectly quiet, hence the cap.
  static Future<void> _waitForFrameQuiet(int maxAttempts) async {
    final binding = SchedulerBinding.instance;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (!binding.hasScheduledFrame && binding.transientCallbackCount == 0) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
}

Future<void> _rasterize(ui.FlutterView view) async {
  const size = Size(240, 180);
  final boundary = RenderRepaintBoundary();
  final pipeline = PipelineOwner();
  final focus = FocusManager();
  final owner = BuildOwner(focusManager: focus);
  final renderView = RenderView(
    view: view,
    configuration: ViewConfiguration(
      logicalConstraints: BoxConstraints.tight(size),
      physicalConstraints: BoxConstraints.tight(size * view.devicePixelRatio),
      devicePixelRatio: view.devicePixelRatio,
    ),
    child: boundary,
  );
  pipeline.rootNode = renderView;
  renderView.prepareInitialFrame();
  RenderObjectToWidgetElement<RenderBox>? root;
  try {
    root = RenderObjectToWidgetAdapter<RenderBox>(
      container: boundary,
      child: ProviderScope(
        overrides: [
          mornyeGlassLevelProvider.overrideWithValue(MornyeGlassLevel.liquid),
          // The warmup tree is exactly where the lens pipeline compiles, so
          // it renders the lens regardless of the global readiness gate.
          mornyeGlassWarmupReadyProvider.overrideWith(
            () => MornyeGlassWarmupReady(initialValue: true),
          ),
        ],
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: MediaQueryData(
              size: size,
              devicePixelRatio: view.devicePixelRatio,
            ),
            child: Theme(
              data: MornyeTheme.build(Brightness.dark),
              child: const Stack(
                fit: StackFit.expand,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xff76534b), Color(0xff385763)],
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.all(12),
                    child: MornyeGlassPanel.overlay(
                      child: Center(child: Text('Download')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ).attachToRenderTree(owner);
    owner.buildScope(root);
    owner.finalizeTree();
    pipeline.flushLayout();
    pipeline.flushCompositingBits();
    pipeline.flushPaint();
    final image = await boundary.toImage(pixelRatio: view.devicePixelRatio);
    image.dispose();
  } finally {
    if (root != null) {
      RenderObjectToWidgetAdapter<RenderBox>(
        container: boundary,
      ).attachToRenderTree(owner, root);
      owner.buildScope(root);
      owner.finalizeTree();
    }
    pipeline.rootNode = null;
    renderView.child = null;
    renderView.dispose();
    boundary.dispose();
    pipeline.dispose();
    focus.dispose();
  }
}
