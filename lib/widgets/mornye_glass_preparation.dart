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
      unawaited(
        MornyeGlassWarmup.prepare(View.of(context)).then((_) {
          // Preparation may bail (view gone, app not resumed) and retry
          // later; only a completed rasterization may open the lens gate.
          if (MornyeGlassWarmup.isReady) {
            ref.read(mornyeGlassWarmupReadyProvider.notifier).markReady();
          }
        }),
      );
    }
    return child;
  }
}
