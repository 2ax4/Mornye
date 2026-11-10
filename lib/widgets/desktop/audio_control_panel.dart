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
const _playbackTempoPrefKey = 'playback.tempo';

/// Restores the saved pitch at startup, before any deck applies it.
void restorePlaybackPitch(SharedPreferences prefs) {
  final semitones = prefs.getDouble(_playbackPitchPrefKey);
  if (semitones == null || semitones == 0) return;
  playbackPitch.value = _pitchFromSemitones(semitones);
}

/// Restores the saved speed at startup, before any deck applies it.
void restorePlaybackTempo(SharedPreferences prefs) {
  final tempo = prefs.getDouble(_playbackTempoPrefKey);
  if (tempo == null || tempo == 1) return;
  playbackTempo.value = tempo.clamp(0.5, 2.0);
}

double _pitchFromSemitones(double semitones) =>
    math.pow(2, semitones / 12).toDouble();

double _semitonesFromPitch(double pitch) =>
    (math.log(pitch <= 0 ? 1 : pitch) / math.log(2)) * 12;

/// The audio control panel: the volume slider with the pitch and speed
/// sliders under it. The player bar's tune button opens it as a popover, and
/// the pitch shift and tempo reach the libmpv decks through [playbackPitch]
/// and [playbackTempo]. Mornye draws the content over the host's glass panel;
/// Material paints its own surface.
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
  double? _speedPreview;

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

  void _commitTempo(double tempo) {
    playbackTempo.value = tempo;
    unawaited(_saveTempo(tempo));
  }

  Future<void> _saveTempo(double tempo) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_playbackTempoPrefKey, tempo);
    } catch (_) {
      // A failed save keeps the speed for this session only.
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
        if (playbackPitchSupported) ...[
          _pitchRow(context, foreground),
          _speedRow(context, foreground),
        ],
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
    final semitones = _preview ?? _semitonesFromPitch(playbackPitch.value);
    String label(double value) => l10n.audioControlPitchSemitones(
      '${value >= 0 ? '+' : ''}${value.toStringAsFixed(1)}',
    );

    // Every drag tick shifts the pitch at once; only the preference save
    // waits for the gesture to end.
    void drag(double value) {
      setState(() => _preview = value);
      playbackPitch.value = _pitchFromSemitones(value);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
      child: Row(
        children: [
          AppIcon(
            Icons.graphic_eq,
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
                // Continuous, so a fine shift such as ×0.94 is reachable.
                label: label(semitones),
                onChanged: drag,
                onChangeEnd: (value) {
                  setState(() => _preview = null);
                  unawaited(_savePitch(value));
                },
              ),
            ),
          ),
          Text(
            '×${_pitchFromSemitones(semitones).toStringAsFixed(2)}',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: foreground.withValues(alpha: 0.7),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          IconButton(
            tooltip: l10n.audioControlPitchReset,
            color: foreground.withValues(alpha: 0.7),
            icon: const AppIcon(Icons.restart_alt),
            onPressed: semitones.abs() < 0.005
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

  Widget _speedRow(BuildContext context, Color foreground) {
    final l10n = context.l10n;
    final tempo = _speedPreview ?? playbackTempo.value;

    // Every drag tick changes the speed at once; only the preference save
    // waits for the gesture to end.
    void drag(double value) {
      setState(() => _speedPreview = value);
      playbackTempo.value = value;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
      child: Row(
        children: [
          AppIcon(
            Icons.speed,
            size: 18,
            color: foreground.withValues(alpha: 0.7),
          ),
          Expanded(
            child: Semantics(
              label: l10n.audioControlSpeed,
              child: Slider(
                key: const ValueKey('audio-control-speed'),
                value: tempo.clamp(0.5, 2.0),
                min: 0.5,
                max: 2.0,
                divisions: 30,
                label: '×${tempo.toStringAsFixed(2)}',
                onChanged: drag,
                onChangeEnd: (value) {
                  setState(() => _speedPreview = null);
                  unawaited(_saveTempo(value));
                },
              ),
            ),
          ),
          Text(
            '×${tempo.toStringAsFixed(2)}',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: foreground.withValues(alpha: 0.7),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          IconButton(
            tooltip: l10n.audioControlSpeedReset,
            color: foreground.withValues(alpha: 0.7),
            icon: const AppIcon(Icons.restart_alt),
            onPressed: (tempo - 1).abs() < 0.005
                ? null
                : () {
                    setState(() => _speedPreview = null);
                    _commitTempo(1);
                  },
          ),
        ],
      ),
    );
  }
}
