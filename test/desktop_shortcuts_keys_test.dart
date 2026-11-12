import 'dart:async';

import 'package:audio_service/audio_service.dart' show PlaybackState;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mornye/l10n/app_localizations.dart';
import 'package:mornye/providers/music_player_provider.dart';
import 'package:mornye/providers/settings_provider.dart';
import 'package:mornye/providers/system_volume_provider.dart';
import 'package:mornye/services/shell_navigation_service.dart';
import 'package:mornye/theme/mornye_theme.dart';
import 'package:mornye/widgets/desktop/desktop_inspector.dart';
import 'package:mornye/widgets/desktop/desktop_shortcuts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fixed_settings.dart';

class _FakeController implements MusicPlayerController {
  final calls = <String>[];

  @override
  Future<void> togglePlayPause(bool isPlaying) async =>
      calls.add(isPlaying ? 'pause' : 'play');

  @override
  Future<void> next() async => calls.add('next');

  @override
  Future<void> previous() async => calls.add('previous');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Sends the desktop shortcuts as real key events through the app's
/// [Shortcuts] layer, so a broken binding or a wrong focus condition can
/// never pass silently.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeController controller;
  late List<double> volumeWrites;
  late StreamController<PlaybackState> states;
  late List<ShellTab> tabRequests;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    controller = _FakeController();
    volumeWrites = [];
    states = StreamController<PlaybackState>();
    tabRequests = [];
    ShellNavigationService.resetHistory(initialTab: ShellTab.home);
    ShellNavigationService.registerTabSelectionHandler(
      owner: 'test',
      handler: tabRequests.add,
    );
    desktopInspectorPanel.value = null;
  });

  tearDown(() {
    ShellNavigationService.unregisterTabSelectionHandler('test');
    ShellNavigationService.resetHistory();
    desktopInspectorPanel.value = null;
    states.close();
  });

  final navigatorKey = GlobalKey<NavigatorState>();

  Widget app(Widget home) => ProviderScope(
    overrides: [
      settingsProvider.overrideWith(() => FixedSettingsNotifier()),
      playbackStateProvider.overrideWith((_) => states.stream),
      musicPlayerControllerProvider.overrideWithValue(controller),
      systemVolumeProvider.overrideWith((_) => Stream.value(0.5)),
      systemVolumeWriterProvider.overrideWithValue((value) async {
        volumeWrites.add(value);
      }),
    ],
    child: MaterialApp(
      navigatorKey: navigatorKey,
      theme: MornyeTheme.build(Brightness.light),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) =>
          DesktopShortcuts(navigatorKey: navigatorKey, child: child!),
      home: home,
    ),
  );

  Future<void> pumpApp(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(home));
    states.add(PlaybackState());
    await tester.pumpAndSettle();
  }

  Future<void> press(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    bool control = false,
    bool shift = false,
  }) async {
    if (control) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    }
    if (shift) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    }
    await tester.sendKeyDownEvent(key);
    await tester.sendKeyUpEvent(key);
    if (shift) {
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    }
    if (control) {
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    }
    await tester.pump();
  }

  testWidgets('space toggles playback with the reported state', (tester) async {
    await pumpApp(tester, const Scaffold(body: SizedBox.shrink()));

    await press(tester, LogicalKeyboardKey.space);
    expect(controller.calls, ['play']);

    // The paused state arrives before the next press, as the real player
    // reports it.
    states.add(PlaybackState(playing: true));
    await tester.pumpAndSettle();

    await press(tester, LogicalKeyboardKey.space);
    expect(controller.calls, ['play', 'pause']);
  });

  testWidgets('control with the arrows runs the transport and the volume', (
    tester,
  ) async {
    await pumpApp(tester, const Scaffold(body: SizedBox.shrink()));

    await press(tester, LogicalKeyboardKey.arrowRight, control: true);
    await press(tester, LogicalKeyboardKey.arrowLeft, control: true);
    expect(controller.calls, ['next', 'previous']);

    await press(tester, LogicalKeyboardKey.arrowUp, control: true);
    await press(tester, LogicalKeyboardKey.arrowDown, control: true);
    expect(volumeWrites, [moreOrLessEquals(0.55), moreOrLessEquals(0.45)]);
  });

  testWidgets('space still toggles playback while a slider holds focus', (
    tester,
  ) async {
    final sliderFocus = FocusNode(debugLabel: 'slider');
    addTearDown(sliderFocus.dispose);
    await pumpApp(
      tester,
      Scaffold(
        body: Center(
          child: Slider(value: 0.4, focusNode: sliderFocus, onChanged: (_) {}),
        ),
      ),
    );

    // Tab traversal or a keyboard nudge leaves the slider focused; sliders
    // use only the arrow keys themselves, so Space must keep working.
    sliderFocus.requestFocus();
    await tester.pump();
    expect(FocusManager.instance.primaryFocus, same(sliderFocus));

    await press(tester, LogicalKeyboardKey.space);
    expect(controller.calls, ['play']);
  });

  testWidgets('a text field keeps space and the arrows to itself', (
    tester,
  ) async {
    final textController = TextEditingController();
    addTearDown(textController.dispose);
    await pumpApp(
      tester,
      Scaffold(
        body: Center(child: TextField(controller: textController)),
      ),
    );

    await tester.enterText(find.byType(TextField), 'song');
    await tester.pump();

    await press(tester, LogicalKeyboardKey.space);
    expect(controller.calls, isEmpty, reason: 'space belongs to the text');
    expect(
      textController.text,
      startsWith('song'),
      reason: 'typing must not be swallowed',
    );

    await press(tester, LogicalKeyboardKey.arrowRight, control: true);
    expect(controller.calls, isEmpty);
    expect(volumeWrites, isEmpty);
  });

  testWidgets('search, settings and the number keys reach the shell', (
    tester,
  ) async {
    await pumpApp(tester, const Scaffold(body: SizedBox.shrink()));

    await press(tester, LogicalKeyboardKey.keyF, control: true);
    expect(tabRequests, [ShellTab.search]);

    await press(tester, LogicalKeyboardKey.comma, control: true);
    expect(tabRequests, [ShellTab.search, ShellTab.settings]);

    await press(tester, LogicalKeyboardKey.digit1, control: true);
    await press(tester, LogicalKeyboardKey.digit2, control: true);
    expect(tabRequests, [
      ShellTab.search,
      ShellTab.settings,
      ShellTab.home,
      ShellTab.library,
    ]);
  });

  testWidgets('back and forward travel the destination history', (
    tester,
  ) async {
    await pumpApp(tester, const Scaffold(body: SizedBox.shrink()));

    // Leave Home for Library, then step back with the shortcut.
    ShellNavigationService.syncState(currentTabIndex: 1);
    await tester.pump();
    await press(tester, LogicalKeyboardKey.bracketLeft, control: true);
    expect(tabRequests, [ShellTab.home]);

    // Forward returns to Library.
    await press(tester, LogicalKeyboardKey.bracketRight, control: true);
    expect(tabRequests, [ShellTab.home, ShellTab.library]);
  });

  testWidgets('shift control u toggles the up next inspector', (tester) async {
    await pumpApp(tester, const Scaffold(body: SizedBox.shrink()));

    expect(desktopInspectorPanel.value, isNull);
    await press(tester, LogicalKeyboardKey.keyU, control: true, shift: true);
    expect(desktopInspectorPanel.value, DesktopInspectorPanel.upNext);

    await press(tester, LogicalKeyboardKey.keyU, control: true, shift: true);
    expect(desktopInspectorPanel.value, isNull);
  });
}
