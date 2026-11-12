import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mornye/l10n/l10n.dart';
import 'package:mornye/models/download_history.dart';
import 'package:mornye/models/unified_library_item.dart';
import 'package:mornye/services/media_kit_playback_deck.dart';
import 'package:mornye/services/playback_deck.dart';
import 'package:mornye/services/playback_output_volume.dart';
import 'package:mornye/theme/mornye_theme.dart';
import 'package:mornye/utils/desktop_platform.dart';
import 'package:mornye/widgets/desktop/audio_control_panel.dart';
import 'package:mornye/widgets/desktop/context_menu.dart';
import 'package:mornye/widgets/desktop/library_track_menu.dart';
import 'package:mornye/widgets/mornye_player_slider.dart';
import 'package:mornye/widgets/player_volume_control.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugDesktopPlatformOverride = true;
    playbackPitch.value = 1;
    playbackTempo.value = 1;
  });

  tearDown(() {
    debugDesktopPlatformOverride = null;
    debugPlaybackEngineOverride = null;
    MediaKitPlaybackDeck.debugAvailableOverride = null;
    playbackPitch.value = 1;
    playbackTempo.value = 1;
    PlaybackOutputVolumeStore.debugReset();
    playbackOutputVolume.value = 1;
  });

  Widget panel() => ProviderScope(
    child: MaterialApp(
      theme: MornyeTheme.build(Brightness.dark),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: Center(child: AudioControlPanel(width: 340))),
    ),
  );

  void enablePitchRows() {
    debugPlaybackEngineOverride = PlaybackEngine.mediaKit;
    MediaKitPlaybackDeck.debugAvailableOverride = true;
  }

  test('the tempo slider maps the track logarithmically around x1.00', () {
    // x1.00 sits at the middle of the track, where the pitch slider's
    // x1.00 (0 semitones) sits.
    expect(tempoFromSliderPosition(0.5), moreOrLessEquals(1.0, epsilon: 1e-9));
    expect(sliderPositionForTempo(1.0), moreOrLessEquals(0.5, epsilon: 1e-9));
    expect(tempoFromSliderPosition(0.0), 0.5);
    expect(tempoFromSliderPosition(1.0), 2.0);
    expect(sliderPositionForTempo(0.5), 0.0);
    expect(sliderPositionForTempo(2.0), 1.0);
  });

  testWidgets('the speed slider rests centered at x1.00 like pitch', (
    tester,
  ) async {
    enablePitchRows();
    await tester.pumpWidget(panel());

    final speed = tester.widget<Slider>(
      find.byKey(const ValueKey('audio-control-speed')),
    );
    final pitch = tester.widget<Slider>(
      find.byKey(const ValueKey('audio-control-pitch')),
    );
    // Both sliders compare by their position along the track: pitch maps
    // semitones (-12..12) while the tempo maps a log scale (0..1), and each
    // must rest at the middle for x1.00.
    double position(Slider slider) =>
        (slider.value - slider.min) / (slider.max - slider.min);
    expect(position(speed), moreOrLessEquals(0.5, epsilon: 1e-9));
    expect(position(pitch), moreOrLessEquals(0.5, epsilon: 1e-9));
    expect(tester.takeException(), isNull);
  });

  testWidgets('dragging the speed slider reaches x0.92', (tester) async {
    enablePitchRows();
    await tester.pumpWidget(panel());

    final speed = tester.widget<Slider>(
      find.byKey(const ValueKey('audio-control-speed')),
    );
    speed.onChanged!(sliderPositionForTempo(0.92));
    await tester.pump();
    expect(playbackTempo.value, moreOrLessEquals(0.92, epsilon: 1e-9));

    speed.onChangeEnd!(sliderPositionForTempo(0.92));
    await tester.pump();
    expect(playbackTempo.value.toStringAsFixed(2), '0.92');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a volume drag shows the floating percentage bubble', (
    tester,
  ) async {
    final volumes = StreamController<double>();
    addTearDown(volumes.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          systemVolumeProvider.overrideWith((ref) => volumes.stream),
          systemVolumeWriterProvider.overrideWith((ref) => (value) async {}),
        ],
        child: MaterialApp(
          theme: MornyeTheme.build(Brightness.dark),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: PlayerVolumeControl()),
        ),
      ),
    );
    volumes.add(0.3);
    await tester.pumpAndSettle();

    final slider = tester.widget<MornyePlayerSlider>(
      find.byType(MornyePlayerSlider),
    );
    slider.onChangeStart!(0.3);
    slider.onChanged!(0.42);
    // One pump builds the bubble portal, the next paints its overlay child.
    await tester.pump();
    await tester.pump();
    // The overlay bubble names the level while the gesture runs.
    expect(find.text('42%'), findsOneWidget);

    slider.onChangeEnd!(0.42);
    await tester.pumpAndSettle();
    expect(find.text('42%'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('releasing a slider leaves no focus that blocks shortcuts', (
    tester,
  ) async {
    enablePitchRows();
    final sliderFocus = FocusNode(debugLabel: 'slider');
    addTearDown(sliderFocus.dispose);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: MornyeTheme.build(Brightness.dark),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Focus(
              focusNode: sliderFocus,
              child: const Center(child: AudioControlPanel(width: 340)),
            ),
          ),
        ),
      ),
    );
    sliderFocus.requestFocus();
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, same(sliderFocus));

    final speed = tester.widget<Slider>(
      find.byKey(const ValueKey('audio-control-speed')),
    );
    speed.onChangeEnd!(sliderPositionForTempo(0.92));
    await tester.pump();
    final focus = FocusManager.instance.primaryFocus;
    expect(
      focus == null || focus is FocusScopeNode,
      isTrue,
      reason: "the shortcuts' idle focus condition must hold again",
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the library context menu offers the tag editor for one file', (
    tester,
  ) async {
    WidgetRef? capturedRef;
    BuildContext? capturedContext;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Consumer(
            builder: (context, ref, _) {
              capturedRef = ref;
              capturedContext = context;
              return const Scaffold(body: SizedBox.shrink());
            },
          ),
        ),
      ),
    );
    final l10n = AppLocalizations.of(capturedContext!);
    final item = UnifiedLibraryItem.fromDownloadHistory(
      DownloadHistoryItem(
        id: 'song',
        trackName: 'Song',
        artistName: 'Artist',
        albumName: 'Album',
        filePath: '/music/song.flac',
        service: 'example-provider',
        downloadedAt: DateTime(2026),
      ),
    );

    List<String> labels(List<List<ContextMenuAction>> groups) => [
      for (final group in groups)
        for (final action in group) action.label,
    ];
    final groups = libraryTrackMenuGroups(
      capturedContext!,
      capturedRef!,
      items: [item],
      onEditTags: () {},
    );
    expect(labels(groups), contains(l10n.trackEditMetadata));

    // Without the callback the menu stays as before.
    final without = libraryTrackMenuGroups(
      capturedContext!,
      capturedRef!,
      items: [item],
    );
    expect(labels(without), isNot(contains(l10n.trackEditMetadata)));
    expect(tester.takeException(), isNull);
  });
}
