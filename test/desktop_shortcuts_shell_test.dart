import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mornye/l10n/app_localizations.dart';
import 'package:mornye/models/settings.dart';
import 'package:mornye/providers/download_queue_provider.dart';
import 'package:mornye/providers/explore_provider.dart';
import 'package:mornye/providers/extension_provider.dart';
import 'package:mornye/providers/music_player_provider.dart';
import 'package:mornye/providers/recent_access_provider.dart';
import 'package:mornye/providers/settings_provider.dart';
import 'package:mornye/routes/now_playing_route.dart';
import 'package:mornye/screens/main_shell.dart';
import 'package:mornye/theme/mornye_theme.dart';
import 'package:mornye/utils/desktop_platform.dart';
import 'package:mornye/widgets/desktop/desktop_shortcuts.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// Drives the real MainShell with the desktop shortcuts: Ctrl+3 opens the
/// Mornye Search tab (its field takes focus), Ctrl+1 returns Home, and the
/// shortcuts must keep working afterwards.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugDesktopPlatformOverride = true;
    addTearDown(() => debugDesktopPlatformOverride = null);
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.zarz.mornye/backend'),
      (call) async => null,
    );
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.zarz.mornye/backend'),
      null,
    );
  });

  Future<_FakeController> pumpShell(
    WidgetTester tester, {
    String whatsNewSeen = '5.3',
  }) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = _FakeController();
    final rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');
    final router = GoRouter(
      navigatorKey: rootKey,
      routes: [GoRoute(path: '/', builder: (_, _) => const MainShell())],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(
            () => _Settings(whatsNewSeen: whatsNewSeen),
          ),
          extensionProvider.overrideWith(() => _Extensions()),
          exploreProvider.overrideWith(_Explore.new),
          downloadHistoryProvider.overrideWith(_History.new),
          recentAccessProvider.overrideWith(_Recent.new),
          musicPlayerControllerProvider.overrideWithValue(controller),
        ],
        child: MaterialApp.router(
          theme: MornyeTheme.build(Brightness.dark),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) =>
              DesktopShortcuts(navigatorKey: rootKey, child: child!),
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    return controller;
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
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('shortcuts survive visiting the search tab', (tester) async {
    final controller = await pumpShell(tester);
    await tester.pump(const Duration(milliseconds: 400));

    // Ctrl+3 opens the Mornye Search tab, whose field takes focus.
    await press(tester, LogicalKeyboardKey.digit3, control: true);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    // Ctrl+1 returns Home.
    await press(tester, LogicalKeyboardKey.digit1, control: true);
    await tester.pump(const Duration(milliseconds: 400));

    await press(tester, LogicalKeyboardKey.space);
    expect(controller.calls, ['play']);
  });

  testWidgets('a full destination hop keeps every shortcut alive', (
    tester,
  ) async {
    final controller = await pumpShell(tester);
    await tester.pump(const Duration(milliseconds: 400));

    // The user hops Ctrl+1, Ctrl+2, Ctrl+3 like reported.
    for (final key in [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
    ]) {
      await press(tester, key, control: true);
    }
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    // Search is open and its field holds the focus.
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorStateOfType<EditableTextState>(),
      isNotNull,
    );

    // Now Ctrl+1 back home and sweep every shortcut.
    await press(tester, LogicalKeyboardKey.digit1, control: true);
    await tester.pump(const Duration(milliseconds: 500));

    await press(tester, LogicalKeyboardKey.space);
    expect(controller.calls, ['play'], reason: 'space must play');

    await press(tester, LogicalKeyboardKey.arrowRight, control: true);
    await press(tester, LogicalKeyboardKey.arrowLeft, control: true);
    expect(controller.calls, ['play', 'next', 'previous']);

    await press(tester, LogicalKeyboardKey.digit2, control: true);
    await tester.pump(const Duration(milliseconds: 300));
    await press(tester, LogicalKeyboardKey.digit1, control: true);
    await tester.pump(const Duration(milliseconds: 300));

    await press(tester, LogicalKeyboardKey.space);
    expect(controller.calls, ['play', 'next', 'previous', 'play']);
  });

  testWidgets('a destination key closes the startup What\'s New dialog', (
    tester,
  ) async {
    // The dialog shows after every update until seen; without this test the
    // destination keys would flip tabs underneath it while it kept the focus
    // — and with it the transport shortcuts — hostage.
    final controller = await pumpShell(tester, whatsNewSeen: '');
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Continue'), findsWidgets);

    await press(tester, LogicalKeyboardKey.digit1, control: true);
    await tester.pumpAndSettle();
    expect(find.text('Continue'), findsNothing);

    await press(tester, LogicalKeyboardKey.space);
    expect(controller.calls, ['play']);
  });

  testWidgets('shortcuts survive a window blur while Now Playing closes', (
    tester,
  ) async {
    final controller = await pumpShell(tester);
    await tester.pump(const Duration(milliseconds: 400));

    // Now Playing sits over the shell.
    final context = tester.element(find.byType(MainShell));
    unawaited(
      Navigator.of(
        context,
        rootNavigator: true,
      ).push(NowPlayingRoute(child: const Scaffold(body: Text('now playing')))),
    );
    await tester.pumpAndSettle();

    // The window loses activation, and while it is out the layer closes
    // (a timer, a queue action, anything): the suspended focus node leaves
    // the tree, so the manager has nothing to restore on resume.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    Navigator.of(context, rootNavigator: true).pop();
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    await press(tester, LogicalKeyboardKey.space);
    expect(controller.calls, ['play'], reason: 'shortcuts must survive blur');
  });

  testWidgets('shortcuts survive closing Now Playing with a destination key', (
    tester,
  ) async {
    final controller = await pumpShell(tester);
    await tester.pump(const Duration(milliseconds: 400));

    // Now Playing sits over the shell, like after tapping the mini player.
    final context = tester.element(find.byType(MainShell));
    unawaited(
      Navigator.of(
        context,
        rootNavigator: true,
      ).push(NowPlayingRoute(child: const Scaffold(body: Text('now playing')))),
    );
    await tester.pumpAndSettle();
    expect(find.text('now playing'), findsOneWidget);

    // Ctrl+1 closes the page and lands Home in one step.
    await press(tester, LogicalKeyboardKey.digit1, control: true);
    await tester.pumpAndSettle();
    expect(find.text('now playing'), findsNothing);

    await press(tester, LogicalKeyboardKey.space);
    expect(controller.calls, ['play']);
  });
}

class _Settings extends SettingsNotifier {
  _Settings({this.whatsNewSeen = '5.3'});

  final String whatsNewSeen;

  @override
  AppSettings build() => AppSettings(
    searchProvider: 'example',
    hasSearchedBefore: true,
    playerMode: 'internal',
    whatsNewSeen: whatsNewSeen,
  );
}

class _Extensions extends ExtensionNotifier {
  @override
  ExtensionState build() => const ExtensionState(isInitialized: true);
}

class _Explore extends ExploreNotifier {
  @override
  ExploreState build() => const ExploreState();
}

class _History extends DownloadHistoryNotifier {
  @override
  DownloadHistoryState build() => DownloadHistoryState();
}

class _Recent extends RecentAccessNotifier {
  @override
  RecentAccessState build() => const RecentAccessState(isLoaded: true);
}
