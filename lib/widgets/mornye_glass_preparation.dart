import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mornye/controllers/mornye_glass_warmup.dart';
import 'package:mornye/providers/runtime_profile_provider.dart';
import 'package:mornye/theme/mornye_theme.dart';

/// Starts the one-time preparation as soon as the device can render the
/// lens, whatever the active style: warming during startup keeps the shader
/// compilation out of a style switch or the first glass frame.
class MornyeGlassPreparation extends ConsumerWidget {
  const MornyeGlassPreparation({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(mornyeGlassLevelProvider) == MornyeGlassLevel.liquid &&
        MornyeTheme.glassClarityOf(context) > 0.2 &&
        !ref.watch(
          mornyeGlassContrastBlockedProvider(
            MediaQuery.highContrastOf(context),
          ),
        )) {
      // Capture the notifier up front: the callback below outlives this
      // widget, and a disposed WidgetRef must never be touched.
      final readiness = ref.read(mornyeGlassWarmupReadyProvider.notifier);
      unawaited(
        MornyeGlassWarmup.prepare(View.of(context)).then((_) async {
          // Preparation may bail (view gone, app not resumed) and retry
          // later; only a completed rasterization may open the lens gate.
          if (!MornyeGlassWarmup.isReady) return;
          // Turning every glass surface to the lens is a heavy frame; land
          // it in a frame-free moment instead of on the entrance or a
          // scroll, capping the wait for UIs that never fully rest.
          final binding = WidgetsBinding.instance;
          for (var attempt = 0; attempt < 30; attempt++) {
            if (!binding.hasScheduledFrame &&
                binding.transientCallbackCount == 0) {
              break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          readiness.markReady();
        }),
      );
    }
    return child;
  }
}
