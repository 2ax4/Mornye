import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mornye/l10n/l10n.dart';
import 'package:mornye/services/media_kit_playback_deck.dart';
import 'package:mornye/services/playback_deck.dart';
import 'package:mornye/theme/mornye_theme.dart';
import 'package:mornye/widgets/app_icon.dart';
import 'package:mornye/widgets/player_volume_control.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _playbackPitchPrefKey = 'playback.pitchSemitones';

/// Restores the saved pitch at startup, before any deck applies it.
void restorePlaybackPitch(SharedPreferences prefs) {
  final semitones = prefs.getDouble(_playbackPitchPrefKey);
  if (semitones == null || semitones == 0) return;
  playbackPitch.value = _pitchFromSemitones(semitones);
}

double _pitchFromSemitones(double semitones) =>
    math.pow(2, semitones / 12).toDouble();

double _semitonesFromPitch(double pitch) =>
    (math.log(pitch <= 0 ? 1 : pitch) / math.log(2)) * 12;

/// The audio control panel: the volume slider with the pitch slider under
/// it. The player bar's volume button opens it as a popover, and the pitch
/// shift reaches the libmpv decks through [playbackPitch]. Mornye draws the
/// content over the host's glass panel; Material paints its own surface.
class AudioControlPanel extends StatefulWidget {
  const AudioControlPanel({super.key, this.width = 320, this.foreground});

  final double width;

  /// Mornye only: the tint of the volume slider and glyphs.
  final Color? foreground;

  @override
  State<AudioControlPanel> createState() => _AudioControlPanelState();
}

class _AudioControlPanelState extends State<AudioControlPanel> {
  /// The slider position while the gesture runs; null reads the notifier.
  double? _preview;

  void _commit(double semitones) {
    playbackPitch.value = _pitchFromSemitones(semitones);
    unawaited(_savePitch(semitones));
  }

  Future<void> _savePitch(double semitones) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_playbackPitchPrefKey, semitones);
    } catch (_) {
      // A failed save keeps the pitch for this session only.
    }
  }

  @override
  Widget build(BuildContext context) {
    final mornye = context.isMornye;
    final foreground =
        widget.foreground ?? Theme.of(context).colorScheme.onSurface;
    Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          key: const ValueKey('desktop-player-volume-popover'),
          height: 48,
          child: PlayerVolumeControl(foreground: foreground),
        ),
        if (playbackPitchSupported) _pitchRow(context, foreground),
      ],
    );
    if (!mornye) {
      content = Material(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: content,
      );
    }
    return SizedBox(width: widget.width, child: content);
  }

  Widget _pitchRow(BuildContext context, Color foreground) {
    final l10n = context.l10n;
    final semitones =
        _preview ?? _semitonesFromPitch(playbackPitch.value).roundToDouble();
    String label(double value) => l10n.audioControlPitchSemitones(
      '${value >= 0 ? '+' : ''}${value.round()}',
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
      child: Row(
        children: [
          AppIcon(
            Icons.tune,
            size: 18,
            color: foreground.withValues(alpha: 0.7),
          ),
          Expanded(
            child: Semantics(
              label: l10n.audioControlPitch,
              child: Slider(
                key: const ValueKey('audio-control-pitch'),
                value: semitones.clamp(-12, 12),
                min: -12,
                max: 12,
                divisions: 24,
                label: label(semitones),
                onChanged: (value) => setState(() => _preview = value),
                onChangeEnd: (value) {
                  setState(() => _preview = null);
                  _commit(value);
                },
              ),
            ),
          ),
          Text(
            label(semitones),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: foreground.withValues(alpha: 0.7),
            ),
          ),
          IconButton(
            tooltip: l10n.audioControlPitchReset,
            color: foreground.withValues(alpha: 0.7),
            icon: const AppIcon(Icons.restart_alt),
            onPressed: semitones == 0
                ? null
                : () {
                    setState(() => _preview = null);
                    _commit(0);
                  },
          ),
        ],
      ),
    );
  }
}
