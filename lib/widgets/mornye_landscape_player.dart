import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mornye/l10n/l10n.dart';
import 'package:mornye/widgets/audio_output_button.dart';

/// Landscape opens on the player, with Up Next on the second page. The cover
/// and header stay in place while the right pane switches.
class MornyeLandscapePlayer extends StatelessWidget {
  const MornyeLandscapePlayer({
    super.key,
    required this.artwork,
    required this.header,
    required this.queue,
    required this.controls,
    this.volume,
    required this.page,
    required this.onPageChanged,
  });

  final Widget artwork;
  final Widget header;
  final Widget queue;
  final Widget controls;

  /// Null when the person hid the volume from the player menu.
  final Widget? volume;
  final int page;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    child: Row(
      children: [
        Expanded(child: artwork),
        Expanded(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: header,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => Stack(
                    fit: StackFit.expand,
                    children: [
                      AnimatedSwitcher(
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 180),
                        layoutBuilder: (current, previous) => Stack(
                          fit: StackFit.expand,
                          children: [
                            for (final child in [...previous, ?current])
                              IgnorePointer(
                                key: child.key,
                                ignoring: child != current,
                                child: ExcludeSemantics(
                                  excluding: child != current,
                                  child: child,
                                ),
                              ),
                          ],
                        ),
                        child: page == 0
                            ? SingleChildScrollView(
                                key: const ValueKey('landscape-controls'),
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    minHeight: constraints.maxHeight,
                                  ),
                                  child: Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceEvenly,
                                    children: [
                                      controls,
                                      ?volume,
                                      const SizedBox(height: 48),
                                    ],
                                  ),
                                ),
                              )
                            : Padding(
                                key: ValueKey(page),
                                padding: const EdgeInsets.only(bottom: 48),
                                child: queue,
                              ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: 48,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const AudioOutputButton(color: Colors.white),
                            IconButton(
                              tooltip: context.l10n.nowPlayingUpNext,
                              icon: const Icon(CupertinoIcons.list_bullet),
                              isSelected: page == 1,
                              color: Colors.white,
                              style: IconButton.styleFrom(
                                backgroundColor: page == 1
                                    ? Colors.white.withValues(alpha: 0.16)
                                    : Colors.transparent,
                              ),
                              onPressed: () => onPageChanged(page == 1 ? 0 : 1),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
