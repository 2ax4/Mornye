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
import 'package:mornye/widgets/desktop/desktop_inspector.dart'
    show desktopInspectorPanel;
import 'package:mornye/widgets/desktop/desktop_shortcuts.dart';
import 'package:mornye/widgets/lazy_tab_view.dart';
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

/// Reproduces the reported "shortcuts break after Ctrl+1/2/3": the Search tab
/// focuses its field, the user hops to another destination, and the hidden
/// field must not keep the shortcuts' key events hostage.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final navigatorKey = GlobalKey<NavigatorState>();
  late FocusNode searchFocus;

  late _FakeController controller;
  late StreamController<PlaybackState> states;
  late ValueNotifier<int> selectedTab;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    controller = _FakeController();
    states = StreamController<PlaybackState>();
    selectedTab = ValueNotifier<int>(0);
    searchFocus = FocusNode(debugLabel: 'search-field');
    ShellNavigationService.resetHistory(initialTab: ShellTab.home);
    ShellNavigationService.registerTabSelectionHandler(
      owner: 'test',
      handler: (tab) {
        final tabs = [
          ShellTab.home,
          ShellTab.library,
          ShellTab.search,
          ShellTab.settings,
        ];
        // MainShell._onNavTap unfocuses before the tab view rebuilds.
        FocusManager.instance.primaryFocus?.unfocus();
        selectedTab.value = tabs.indexOf(tab);
        if (tab == ShellTab.search) {
          // ShellNavigationService.requestSearch focuses the search field
          // from a post-frame callback after the tab view switches.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (selectedTab.value == 2) searchFocus.requestFocus();
          });
        }
      },
    );
    desktopInspectorPanel.value = null;
  });

  tearDown(() {
    ShellNavigationService.unregisterTabSelectionHandler('test');
    ShellNavigationService.resetHistory();
    desktopInspectorPanel.value = null;
    states.close();
    selectedTab.dispose();
    searchFocus.dispose();
  });

  Widget app() => ProviderScope(
    overrides: [
      settingsProvider.overrideWith(() => FixedSettingsNotifier()),
      playbackStateProvider.overrideWith((_) => states.stream),
      musicPlayerControllerProvider.overrideWithValue(controller),
      systemVolumeProvider.overrideWith((_) => Stream.value(0.5)),
      systemVolumeWriterProvider.overrideWithValue((value) async {}),
    ],
    child: MaterialApp(
      navigatorKey: navigatorKey,
      theme: MornyeTheme.build(Brightness.light),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) =>
          DesktopShortcuts(navigatorKey: navigatorKey, child: child!),
      home: ValueListenableBuilder<int>(
        valueListenable: selectedTab,
        builder: (context, index, _) => Scaffold(
          body: LazyTabView(
            index: index,
            children: [
              // Home.
              Navigator(
                onGenerateInitialRoutes: (_, _) => [
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(body: SizedBox.shrink()),
                  ),
                ],
              ),
              // Library.
              Navigator(
                onGenerateInitialRoutes: (_, _) => [
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(body: SizedBox.shrink()),
                  ),
                ],
              ),
              // Search: its field takes focus when the tab opens, like
              // HomeTab does after ShellNavigationService.requestSearch.
              Navigator(
                onGenerateInitialRoutes: (_, _) => [
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      body: Center(child: TextField(focusNode: searchFocus)),
                    ),
                  ),
                ],
              ),
              // Settings.
              Navigator(
                onGenerateInitialRoutes: (_, _) => [
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(body: SizedBox.shrink()),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    states.add(PlaybackState());
    await tester.pumpAndSettle();
  }

  Future<void> press(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    bool control = false,
  }) async {
    if (control) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    }
    await tester.sendKeyDownEvent(key);
    await tester.sendKeyUpEvent(key);
    if (control) {
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    }
    await tester.pump();
  }

  testWidgets('leaving the focused search tab frees the shortcuts', (
    tester,
  ) async {
    await pumpApp(tester);

    // Ctrl+3 opens Search, whose field takes focus post-frame.
    await press(tester, LogicalKeyboardKey.digit3, control: true);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorStateOfType<EditableTextState>(),
      isNotNull,
    );

    // Ctrl+1 returns Home. The hidden Search tab keeps its field mounted,
    // but the field must not hold the focus from there on.
    await press(tester, LogicalKeyboardKey.digit1, control: true);
    await tester.pumpAndSettle();

    final focus = FocusManager.instance.primaryFocus;
    final editing =
        focus?.context?.findAncestorStateOfType<EditableTextState>() != null;
    expect(editing, isFalse, reason: 'no visible text field remains');

    await press(tester, LogicalKeyboardKey.space);
    expect(controller.calls, ['play']);

    await press(tester, LogicalKeyboardKey.arrowRight, control: true);
    expect(controller.calls, ['play', 'next']);
  });

  testWidgets('hopping home, library, search and back keeps shortcuts alive', (
    tester,
  ) async {
    await pumpApp(tester);

    for (final key in [
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit1,
    ]) {
      await press(tester, key, control: true);
      await tester.pumpAndSettle();
    }
    // Destination hopping alone must never trap the shortcuts, even though
    // the Search tab focused its field while it was open.
    await press(tester, LogicalKeyboardKey.space);
    expect(controller.calls, ['play']);
  });
}
