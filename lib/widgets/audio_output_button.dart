import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mornye/l10n/l10n.dart';
import 'package:mornye/utils/logger.dart';
import 'package:mornye/widgets/app_bottom_sheet.dart';
import 'package:mornye/widgets/app_icon_button.dart';
import 'package:mornye/widgets/expressive_icon_button.dart';

enum _OutputChoice { system }

class AudioOutputButton extends StatefulWidget {
  const AudioOutputButton({
    super.key,
    this.color,
    this.backgroundColor,
    this.width = 48,
    this.onPickerChanged,
  });

  final Color? color;

  final Color? backgroundColor;
  final double width;
  final ValueChanged<bool>? onPickerChanged;

  @override
  State<AudioOutputButton> createState() => _AudioOutputButtonState();
}

class _AudioOutputButtonState extends State<AudioOutputButton> {
  static const _systemChannel = MethodChannel('com.zarz.mornye/audio_output');
  bool _opening = false;

  bool get _ios => defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> _showPicker() async {
    if (_opening) return;
    _opening = true;
    widget.onPickerChanged?.call(true);
    var opened = false;
    try {
      final choice = await showAppBottomSheet<_OutputChoice>(
        context: context,
        title: context.l10n.nowPlayingAudioOutput,
        builder: (context) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppSheetOption(
              title: Text(
                _ios
                    ? context.l10n.audioOutputAirPlay
                    : context.l10n.audioOutputSystem,
              ),
              leading: Icon(
                _ios ? Icons.airplay : Icons.speaker_group_outlined,
              ),
              onTap: () => Navigator.pop(context, _OutputChoice.system),
            ),
          ],
        ),
      );
      if (choice == null || !mounted) return;
      switch (choice) {
        case _OutputChoice.system:
          opened = await _systemChannel.invokeMethod<bool>('show') ?? false;
      }
    } on PlatformException {
      // Show a visible failure instead of leaving an unresponsive control.
    } on MissingPluginException {
      // The native bridge is not available on unsupported builds.
    } on Object catch (error) {
      AppLogger('AudioOutput').w('Could not open output picker: $error');
    } finally {
      _opening = false;
      if (mounted) widget.onPickerChanged?.call(false);
    }
    if (mounted && !opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.nowPlayingAudioOutputUnavailable)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return const SizedBox.shrink();
    return switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS => _button(context),
      _ => const SizedBox.shrink(),
    };
  }

  Widget _button(BuildContext context) {
    final icon = _ios ? Icons.airplay : Icons.speaker_group_outlined;
    if (widget.backgroundColor case final background?) {
      return ExpressiveIconButton(
        tooltip: context.l10n.nowPlayingAudioOutput,
        width: widget.width,
        foregroundColor: widget.color,
        backgroundColor: background,
        icon: Icon(icon),
        onPressed: _showPicker,
      );
    }
    return AppIconButton(
      tooltip: context.l10n.nowPlayingAudioOutput,
      color: widget.color,
      icon: Icon(icon),
      onPressed: _showPicker,
    );
  }
}
