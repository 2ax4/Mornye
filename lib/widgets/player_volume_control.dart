import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mornye/l10n/l10n.dart';
import 'package:mornye/providers/music_player_provider.dart';
import 'package:mornye/providers/system_volume_provider.dart';
import 'package:mornye/theme/mornye_theme.dart';
import 'package:mornye/widgets/app_icon.dart';
import 'package:mornye/widgets/app_slider.dart';
import 'package:mornye/widgets/desktop/desktop_volume_scroll.dart';
import 'package:mornye/widgets/mornye_player_slider.dart';
import 'package:mornye/widgets/slider_value_bubble.dart';
import 'package:mornye/utils/logger.dart';
import 'package:mornye/services/music_playback_deck.dart';

export 'package:mornye/providers/system_volume_provider.dart';

/// System (or USB hardware) volume slider for the player and USB settings.
/// Mornye draws its glass slider between speaker glyphs; Material draws the
/// expressive slider between volume icons.
class PlayerVolumeControl extends ConsumerStatefulWidget {
  const PlayerVolumeControl({
    super.key,
    this.foreground = Colors.white,
    this.onSpeakerTap,
  });

  /// Mornye only: the tint of the slider and glyphs over the player artwork.
  final Color foreground;

  /// Called when the trailing tune glyph is tapped, opening the audio
  /// control panel where one is available. Null leaves it inert.
  final void Function()? onSpeakerTap;

  @override
  ConsumerState<PlayerVolumeControl> createState() =>
      _PlayerVolumeControlState();
}

class _PlayerVolumeControlState extends ConsumerState<PlayerVolumeControl> {
  double? _preview;
  double? _pendingVolume;
  bool _dragging = false;
  bool _writing = false;

  /// Leaves the focus the gesture gave the slider, so keyboard shortcuts
  /// (Space, the arrow keys) reach the app again after the drag.
  void _releaseSliderFocus() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  void _setVolume(double value) {
    if (value > 0) volumeBeforeMute.value = value;
    setState(() => _preview = value);
    _pendingVolume = value;
    if (!_writing) unawaited(_flushVolume());
  }

  /// The leading volume glyph mutes: it remembers the level it muted from
  /// and restores it on the next tap.
  void _toggleMute(double value) {
    if (value > 0) {
      volumeBeforeMute.value = value;
      _setVolume(0);
    } else {
      _setVolume(volumeBeforeMute.value.clamp(0.05, 1.0));
    }
  }

  Future<void> _flushVolume() async {
    _writing = true;
    final remote = ref.read(activeRemotePlaybackProvider);
    final write = remote == null
        ? ref.read(systemVolumeWriterProvider)
        : remote.setVolume;
    final usbToken = usbHardwareVolume.value?.token;
    try {
      // Send changes during the gesture. If the platform is still processing
      // a write, keep only the newest value instead of queuing stale positions.
      while (mounted && _pendingVolume != null) {
        if (usbHardwareVolume.value?.token != usbToken) {
          _pendingVolume = null;
          break;
        }
        final value = _pendingVolume!;
        _pendingVolume = null;
        try {
          await write(value);
        } catch (error) {
          AppLogger('PlayerVolume').w('Could not set system volume: $error');
        }
      }
    } finally {
      _writing = false;
      if (mounted && !_dragging) setState(() => _preview = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    // While another device plays in this one's place, the slider sets its
    // volume.
    final remote = ref.watch(activeRemotePlaybackProvider) != null;
    final usb = remote
        ? null
        : ref.watch(usbVolumeProvider).value ?? usbHardwareVolume.value;
    final volume = remote
        ? ref.watch(activeRemoteVolumeProvider).value
        : usb == null
        ? ref.watch(systemVolumeProvider).value
        : usb.available
        ? usb.fraction
        : null;
    final value = (_preview ?? volume ?? 0).clamp(0.0, 1.0);
    String percentage(double volume) => '${(volume * 100).round()}%';
    final control = Semantics(
      label: usb == null
          ? context.l10n.nowPlayingVolume
          : context.l10n.usbHardwareVolume,
      slider: true,
      enabled: volume != null,
      excludeSemantics: true,
      value: volume == null ? null : percentage(value),
      increasedValue: volume == null
          ? null
          : percentage((value + 0.05).clamp(0, 1)),
      decreasedValue: volume == null
          ? null
          : percentage((value - 0.05).clamp(0, 1)),
      onIncrease: volume == null
          ? null
          : () => _setVolume((value + 0.05).clamp(0, 1)),
      onDecrease: volume == null
          ? null
          : () => _setVolume((value - 0.05).clamp(0, 1)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: SliderValueBubble(
          visible: _dragging,
          label: volume == null ? '' : percentage(value),
          child: !context.isMornye
              ? _materialSlider(context, value, enabled: volume != null)
              : Row(
                  children: [
                    Icon(
                      CupertinoIcons.speaker_fill,
                      size: 16,
                      color: widget.foreground.withValues(alpha: 0.54),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) => IgnorePointer(
                          ignoring: volume == null,
                          child: Opacity(
                            opacity: volume == null ? 0.4 : 1,
                            child: MornyePlayerSlider(
                              value: value,
                              activeColor: widget.foreground.withValues(
                                alpha: 0.70,
                              ),
                              inactiveColor: widget.foreground.withValues(
                                alpha: 0.12,
                              ),
                              onChangeStart: (_) => _dragging = true,
                              onChanged: _setVolume,
                              onChangeEnd: (value) {
                                _dragging = false;
                                _setVolume(value);
                                _releaseSliderFocus();
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Icon(
                      CupertinoIcons.speaker_3_fill,
                      size: 16,
                      color: widget.foreground.withValues(alpha: 0.54),
                    ),
                  ],
                ),
        ),
      ),
    );
    return DesktopVolumeScroll(child: control);
  }

  /// The expressive slider has no drag-start callback, so the pointer marks
  /// the drag that keeps system-volume echoes from resetting the thumb.
  Widget _materialSlider(
    BuildContext context,
    double value, {
    required bool enabled,
  }) {
    final colors = Theme.of(context).colorScheme;
    void release() {
      if (!_dragging) return;
      _dragging = false;
      if (!_writing && mounted) setState(() => _preview = null);
    }

    return Row(
      children: [
        GestureDetector(
          onTap: enabled ? () => _toggleMute(value) : null,
          child: Tooltip(
            message: context.l10n.nowPlayingVolume,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: AppIcon(
                value <= 0
                    ? Icons.volume_off_rounded
                    : value < 0.5
                    ? Icons.volume_down_rounded
                    : Icons.volume_up_rounded,
                size: 22,
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: IgnorePointer(
            ignoring: !enabled,
            child: Opacity(
              opacity: enabled ? 1 : 0.4,
              child: Listener(
                onPointerDown: (_) => _dragging = true,
                onPointerUp: (_) => release(),
                onPointerCancel: (_) => release(),
                child: ClipRect(
                  // The expressive slider paints its built-in value bubble
                  // above the track, where the panel's rounded clip cuts it
                  // in half. Clip it here and let the floating bubble name
                  // the value instead.
                  child: AppSlider(
                    // As thin as the seek bar above it, with a shorter
                    // handle, so volume stays secondary to it.
                    trackThickness: 4,
                    thumbLength: 20,
                    value: value,
                    onChanged: enabled ? _setVolume : null,
                    onChangeEnd: (value) {
                      _setVolume(value);
                      _releaseSliderFocus();
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        // The tune glyph opens the audio control panel where one is
        // available; without one, the slider keeps the room to itself.
        if (widget.onSpeakerTap != null)
          GestureDetector(
            onTap: widget.onSpeakerTap,
            child: Tooltip(
              message: context.l10n.audioControlTitle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: AppIcon(
                  Icons.tune,
                  size: 22,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
