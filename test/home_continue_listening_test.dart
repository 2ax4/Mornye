import 'dart:async';

import 'package:audio_service/audio_service.dart' show MediaItem;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mornye/l10n/app_localizations.dart';
import 'package:mornye/models/settings.dart';
import 'package:mornye/providers/download_queue_provider.dart';
import 'package:mornye/providers/explore_provider.dart';
import 'package:mornye/providers/extension_provider.dart';
import 'package:mornye/providers/library_mixes_provider.dart';
import 'package:mornye/providers/music_player_provider.dart';
import 'package:mornye/providers/recent_access_provider.dart';
import 'package:mornye/providers/settings_provider.dart';
import 'package:mornye/screens/home_tab.dart';
import 'package:mornye/services/playable_media.dart';
import 'package:mornye/theme/app_theme.dart';
import 'package:mornye/utils/desktop_platform.dart';
import 'package:mornye/widgets/player_artwork.dart';

import 'support/fixed_settings.dart';

const _cover = 'network://nas/Album/cover.jpg';

/// The Material Home without a feed, resuming a saved song unless
/// [saved] is false. [settled] false keeps the startup restore running, and
/// [sessionSong] stands in as the saved session's own current track.
Widget _home({bool saved = true, bool settled = true, String? sessionSong}) =>
    ProviderScope(
      overrides: [
        settingsProvider.overrideWith(
          () => FixedSettingsNotifier(
            const AppSettings(
              searchProvider: 'example',
              homeFeedProvider: AppSettings.homeFeedProviderOff,
              hasSearchedBefore: true,
            ),
          ),
        ),
        extensionProvider.overrideWith(_Extensions.new),
        exploreProvider.overrideWith(_Explore.new),
        downloadHistoryProvider.overrideWith(_History.new),
        recentAccessProvider.overrideWith(_Recent.new),
        libraryMixesProvider.overrideWith((ref) async => const []),
        playerUiEnabledProvider.overrideWithValue(true),
        currentMediaItemProvider.overrideWithBuild(
          (ref, notifier) => Stream<MediaItem?>.value(null),
        ),
        playbackResumeProvider.overrideWith(
          (ref) async => saved
              ? (
                  media: const PlayableMedia(
                    id: 'network://nas/Album/song.flac',
                    source: 'network://nas/Album/song.flac',
                    title: 'Saved song',
                    artist: 'Artist',
                    networkArtworkSource: _cover,
                  ),
                  position: const Duration(seconds: 23),
                )
              : null,
        ),
        if (sessionSong != null)
          playbackSessionPreviewProvider.overrideWith(
            (ref) async => (
              media: PlayableMedia(
                id: 'network://nas/Album/session.flac',
                source: 'network://nas/Album/session.flac',
                title: sessionSong,
                artist: 'Artist',
                networkArtworkSource: _cover,
              ),
              position: const Duration(seconds: 40),
            ),
          ),
        playbackRestoreSettledProvider.overrideWith((ref) async {
          if (settled) return;
          return Completer<void>().future;
        }),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const HomeTab(mode: HomeTabMode.combined),
      ),
    );

/// Opens [_home] in a [width] wide window, as the desktop app when
/// [desktop] is true.
Future<void> _open(
  WidgetTester tester, {
  required bool desktop,
  double width = 1280,
  bool saved = true,
}) async {
  tester.view.physicalSize = Size(width, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  debugDesktopPlatformOverride = desktop;
  addTearDown(() => debugDesktopPlatformOverride = null);
  await tester.pumpWidget(_home(saved: saved));
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('Continue listening shows a network cover not stored yet', (
    tester,
  ) async {
    const cover = _cover;
    await tester.pumpWidget(_home());
    await tester.pump();
    await tester.pump();

    final card = find.ancestor(
      of: find.text('Saved song'),
      matching: find.byType(InkWell),
    );
    final artwork = find.descendant(
      of: card.first,
      matching: find.byType(PlayerArtwork),
    );
    expect(tester.widget<PlayerArtwork>(artwork).artUri, cover);
  });

  testWidgets('desktop Home sets the shortcuts beside Continue listening', (
    tester,
  ) async {
    await _open(tester, desktop: true);
    expect(tester.takeException(), isNull);

    final continueHeader = tester.getRect(find.text('Continue listening'));
    final shortcutsHeader = tester.getRect(find.text('Shortcuts'));
    expect(shortcutsHeader.top, continueHeader.top);
    expect(shortcutsHeader.left, greaterThan(continueHeader.left + 400));

    // The shortcuts stack in one list as tall as the card beside it.
    final card = tester.getRect(
      find
          .ancestor(of: find.text('Saved song'), matching: find.byType(InkWell))
          .first,
    );
    final first = tester.getRect(
      find
          .ancestor(
            of: find.text('Shuffle library'),
            matching: find.byType(InkWell),
          )
          .first,
    );
    final last = tester.getRect(
      find
          .ancestor(
            of: find.text('Listening statistics'),
            matching: find.byType(InkWell),
          )
          .first,
    );
    expect(first.left, moreOrLessEquals(last.left, epsilon: 0.01));
    expect(first.top, card.top);
    expect(last.bottom, moreOrLessEquals(card.bottom, epsilon: 0.01));
    expect(first.height, greaterThanOrEqualTo(48));
  });

  testWidgets('desktop Home stacks both sections in a narrow pane', (
    tester,
  ) async {
    await _open(tester, desktop: true, width: 700);
    expect(tester.takeException(), isNull);
    expect(
      tester.getRect(find.text('Shortcuts')).top,
      greaterThan(tester.getRect(find.text('Saved song')).bottom),
    );
    // One row of shortcuts.
    expect(
      tester.getRect(find.text('Listening statistics')).top,
      tester.getRect(find.text('Shuffle library')).top,
    );
  });

  testWidgets('desktop Home without a session shows the shortcuts in a row', (
    tester,
  ) async {
    await _open(tester, desktop: true, saved: false);
    expect(tester.takeException(), isNull);
    expect(find.text('Continue listening'), findsNothing);
    // Labels may wrap; the tiles share one row and one height.
    final tiles = {
      for (final label in [
        'Shuffle library',
        'Equalizer',
        'Listening statistics',
      ])
        tester.getRect(
          find
              .ancestor(of: find.text(label), matching: find.byType(InkWell))
              .first,
        ),
    };
    expect({for (final tile in tiles) (tile.top, tile.height)}, hasLength(1));
  });

  testWidgets("the restore's own song stands in while the restore runs", (
    tester,
  ) async {
    // The dismissed player's archive is older than the session the restore
    // is bringing back: the card must hold it back and preview the
    // session's own track instead.
    await tester.pumpWidget(
      _home(settled: false, saved: true, sessionSong: 'Session song'),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Session song'), findsOneWidget);
    expect(find.text('Saved song'), findsNothing);
    expect(find.text('Continue listening'), findsOneWidget);
  });

  testWidgets('the saved session alone holds the section open pre-restore', (
    tester,
  ) async {
    await tester.pumpWidget(
      _home(settled: false, saved: false, sessionSong: 'Session song'),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Continue listening'), findsOneWidget);
    expect(find.text('Session song'), findsOneWidget);
  });

  testWidgets('phones keep two columns of shortcuts under the card', (
    tester,
  ) async {
    await _open(tester, desktop: false, width: 400);
    expect(tester.takeException(), isNull);
    final shuffle = tester.getRect(find.text('Shuffle library'));
    expect(tester.getRect(find.text('Equalizer')).top, shuffle.top);
    expect(
      tester.getRect(find.text('Listening statistics')).top,
      greaterThan(shuffle.bottom),
    );
    expect(
      tester.getRect(find.text('Shortcuts')).top,
      greaterThan(tester.getRect(find.text('Saved song')).bottom),
    );
  });
}

class _Extensions extends ExtensionNotifier {
  @override
  ExtensionState build() => const ExtensionState();
}

class _Explore extends ExploreNotifier {
  @override
  ExploreState build() => const ExploreState();

  @override
  Future<void> fetchHomeFeed({bool forceRefresh = false}) async {}
}

class _History extends DownloadHistoryNotifier {
  @override
  DownloadHistoryState build() => DownloadHistoryState();
}

class _Recent extends RecentAccessNotifier {
  @override
  RecentAccessState build() => const RecentAccessState(isLoaded: true);
}
