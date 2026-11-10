import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:mornye/controllers/clickable_metadata.dart';
import 'package:mornye/controllers/player_track_navigation.dart';
import 'package:mornye/controllers/player_metadata_controller.dart';
import 'package:mornye/l10n/l10n.dart';
import 'package:mornye/providers/library_collections_provider.dart';
import 'package:mornye/providers/music_player_provider.dart';
import 'package:mornye/providers/settings_provider.dart';
import 'package:mornye/routes/now_playing_route.dart';
import 'package:mornye/screens/equalizer_screen.dart';
import 'package:mornye/theme/mornye_theme.dart';
import 'package:mornye/theme/player_artwork_theme.dart';
import 'package:mornye/utils/file_access.dart';
import 'package:mornye/utils/playback_seek_preview.dart';
import 'package:mornye/widgets/app_bottom_sheet.dart';
import 'package:mornye/widgets/app_snack_bar.dart';
import 'package:mornye/widgets/app_icon.dart';
import 'package:mornye/widgets/app_icon_button.dart';
import 'package:mornye/widgets/audio_output_button.dart';
import 'package:mornye/widgets/desktop/desktop_commands.dart'
    show DesktopCommand, desktopTooltip;
import 'package:mornye/widgets/desktop/desktop_inspector.dart';
import 'package:mornye/widgets/link/link_actions.dart';
import 'package:mornye/widgets/network_offline_actions.dart';
import 'package:mornye/widgets/link/link_devices_sheet.dart';
import 'package:mornye/widgets/player_artwork.dart';
import 'package:mornye/widgets/player_gesture_regions.dart';
import 'package:mornye/widgets/player_playback_controls.dart';
import 'package:mornye/widgets/player_queue_sheet.dart';
import 'package:mornye/widgets/player_details_sheet.dart';
import 'package:mornye/widgets/material_player_backdrop.dart';
import 'package:mornye/widgets/material_player_layout.dart';
import 'package:mornye/widgets/mornye_player_layout.dart';
import 'package:mornye/widgets/playlist_picker_sheet.dart';
import 'package:mornye/widgets/settings_group.dart';
import 'package:mornye/widgets/mornye_player_background.dart';
import 'package:mornye/widgets/mornye_artwork_contrast.dart';
import 'package:mornye/widgets/mornye_player_actions_sheet.dart';
import 'package:mornye/widgets/mornye_context_menu.dart';
import 'package:mornye/widgets/mornye_player_artwork.dart';
import 'package:mornye/providers/player_motion_artwork_provider.dart';

export 'package:mornye/routes/now_playing_route.dart';

/// Portrait's "Playing on" row, kept while empty.
const _playingOnRowHeight = 36.0;

/// Screens shorter than this keep Mornye's volume row clear by leaving the
/// empty row out; its cover and controls need the height.
const _mornyePlayingOnMinScreenHeight = 720.0;

/// What Mornye holds back above its volume row, so the toolbar reaches
/// Material's height while the track header stays level with Material's.
const _mornyeControlsHeadroom = 20.0;

/// How much of an iPhone's home indicator inset stays under that row. The
/// indicator sits in the screen's bottom 13pt, and the label's text ends 8pt
/// above the row's bottom, so it still clears the indicator.
const _homeIndicatorBelowRow = 12.0;

/// AppBar wrapper that fades with the route transition (see contentOpacity
/// in [_NowPlayingScreenState.build]).
class _FadingAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Animation<double> opacity;
  final AppBar child;

  const _FadingAppBar({required this.opacity, required this.child});

  @override
  Size get preferredSize => child.preferredSize;

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: opacity, child: child);
}

class NowPlayingScreen extends ConsumerStatefulWidget {
  const NowPlayingScreen({
    super.key,
    this.metadataControllerFactory,
    this.embedded = false,
  });

  final PlayerMetadataController Function()? metadataControllerFactory;

  /// Shown in the desktop content pane rather than as a route. Minimizing
  /// returns to the content, and Up Next opens in the desktop inspector
  /// beside the player instead of replacing it.
  final bool embedded;

  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen> {
  ProviderSubscription<AsyncValue<MediaItem?>>? _mediaItemSub;
  late final _trackMetadata =
      widget.metadataControllerFactory?.call() ?? PlayerMetadataController();
  int _currentPage = 0;
  bool _landscape = false;
  bool _queueSheetShowing = false;
  String? _measuredMotionSource;
  double? _motionAspectRatio;
  String? _failedMotionSource;
  final _artworkHeaderKey = GlobalKey();
  final _artworkControlsKey = GlobalKey();
  final _artworkVolumeKey = GlobalKey();
  final _expandedArtworkKey = GlobalKey();
  final _compactArtworkKey = GlobalKey();
  final _motionArtworkKey = GlobalKey();
  final _artworkForeground = ValueNotifier<Map<String, Color>>({});
  final _seekPreview = PlaybackSeekPreview();
  NowPlayingRoute? _artworkRoute;

  @override
  void initState() {
    super.initState();
    if (widget.embedded) desktopInspectorPanel.addListener(_onInspectorChanged);
    _mediaItemSub = ref.listenManual<AsyncValue<MediaItem?>>(
      currentMediaItemProvider,
      (previous, next) {
        if (previous?.value?.id != next.value?.id) _seekPreview.reset();
        unawaited(_trackMetadata.load(next.value));
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_trackMetadata.load(ref.read(currentMediaItemProvider).value));
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final size = MediaQuery.sizeOf(context);
    _landscape = context.isMornye && size.width > size.height;
  }

  void _onInspectorChanged() {
    if (mounted) setState(() {});
  }

  /// Whether the Up Next toggle shows as selected. The embedded player shows
  /// it in the desktop inspector instead.
  bool _showsPage(int page) => widget.embedded
      ? desktopInspectorPanel.value == DesktopInspectorPanel.upNext
      : _currentPage == page;

  /// Opens Up Next in the desktop inspector when embedded.
  /// Returns false when the player should switch pages itself.
  bool _toggleInspector(int page) {
    if (!widget.embedded) return false;
    if (page == 1) toggleDesktopInspector(DesktopInspectorPanel.upNext);
    return true;
  }

  String _minimizeTooltip(BuildContext context) => desktopTooltip(
    context,
    context.l10n.nowPlayingMinimize,
    DesktopCommand.dismiss,
  );

  void _minimize() {
    if (widget.embedded) {
      desktopNowPlayingOpen.value = false;
    } else {
      unawaited(Navigator.of(context).maybePop());
    }
  }

  @override
  void dispose() {
    if (widget.embedded) {
      desktopInspectorPanel.removeListener(_onInspectorChanged);
    }
    _artworkRoute?.readArtwork = null;
    _mediaItemSub?.close();
    _trackMetadata.dispose();
    _artworkForeground.dispose();
    _seekPreview.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(playerUiEnabledProvider)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ModalRoute.of(context)?.isCurrent == true) {
          Navigator.of(context).maybePop();
        }
      });
      return const SizedBox.shrink();
    }
    final mediaItem = ref.watch(currentMediaItemProvider).value;
    final mornye = context.isMornye;
    final fullScreenCover = ref.watch(
      settingsProvider.select(
        (s) => s.playerCoverStyleFor(mornye: mornye) == 'fullscreen',
      ),
    );
    return mornye
        ? _buildPlayer(context, mediaItem, fullScreenCover: fullScreenCover)
        // Material takes the track's artwork scheme. The providers it needs
        // are read above, so the scoped builder reads none.
        : PlayerArtworkTheme(
            artUri: mediaItem?.artUri?.toString(),
            child: Builder(
              builder: (context) => _buildPlayer(
                context,
                mediaItem,
                fullScreenCover: fullScreenCover,
              ),
            ),
          );
  }

  Widget _buildPlayer(
    BuildContext context,
    MediaItem? mediaItem, {
    required bool fullScreenCover,
  }) {
    final mornye = context.isMornye;
    final colorScheme = mornye
        ? MornyeTheme.fromContext(
            context,
            brightness: Brightness.dark,
          ).colorScheme
        : Theme.of(context).colorScheme;

    if (mediaItem == null) {
      return Scaffold(
        appBar: AppBar(
          leading: AppIconButton(
            tooltip: _minimizeTooltip(context),
            icon: const AppIcon(Icons.keyboard_arrow_down),
            onPressed: _minimize,
          ),
        ),
        body: Center(child: Text(context.l10n.nowPlayingNothingPlaying)),
      );
    }

    final source = mediaItem.extras?['source']?.toString() ?? '';
    final motionState =
        mornye &&
            ref.watch(settingsProvider.select((s) => s.motionArtworkEnabled)) &&
            !MediaQuery.disableAnimationsOf(context)
        ? ref.watch(
            playerMotionArtworkProvider((
              album: mediaItem.album ?? '',
              artist: mediaItem.artist ?? '',
            )),
          )
        : null;
    final resolvedMotion = motionState?.value;
    final motionArtwork = resolvedMotion?.source == _failedMotionSource
        ? null
        : resolvedMotion;
    final motionRatio =
        motionArtwork?.aspectRatio ??
        (_measuredMotionSource == motionArtwork?.source
            ? _motionAspectRatio
            : null);
    final squareArtwork =
        motionArtwork == null || (motionRatio != null && motionRatio >= 0.95);
    // Motion artwork is always full-bleed in Mornye; still covers follow the
    // cover style setting through the same layout, as a square video would.
    final fullBleed = mornye && (motionArtwork != null || fullScreenCover);
    final screen = MediaQuery.sizeOf(context);
    // A still cover is cropped at the sides to reach down to the title, as
    // in the Material full-screen style; landscape keeps the square card.
    final stillFullBleed = fullBleed && motionArtwork == null;
    final artworkRatio = stillFullBleed
        ? _landscape || screen.height <= 0
              ? 1.0
              : (screen.width / (screen.height * 0.56)).clamp(0.5, 1.0)
        : motionRatio;
    final materialBackdrop = !mornye && fullScreenCover;
    // Two-pane landscape keeps its side-by-side cover over the blurred surface.
    final materialFullScreen =
        materialBackdrop &&
        MediaQuery.orientationOf(context) == Orientation.portrait;
    final overCover = materialFullScreen;
    // Portrait keeps the "Playing on" row while empty, so the controls stay
    // put when a computer takes over playback. On an iPhone the row reaches
    // into the home indicator's inset rather than stacking a second empty
    // band on top of it.
    final reservesPlayingOnRow =
        MediaQuery.orientationOf(context) == Orientation.portrait &&
        screen.height >= (mornye ? _mornyePlayingOnMinScreenHeight : 640);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final homeIndicatorBelowRow =
        reservesPlayingOnRow && Theme.of(context).platform == TargetPlatform.iOS
        ? bottomInset.clamp(0.0, _homeIndicatorBelowRow)
        : null;
    if (!fullBleed && _artworkForeground.value.isNotEmpty) {
      _artworkForeground.value = {};
    }
    Widget artwork() => MornyePlayerArtwork(
      mediaItem: mediaItem,
      videoUrl: motionArtwork?.source,
      resolvingVideo: motionState?.isLoading == true,
      onAspectRatioChanged: (ratio) {
        if (!mounted ||
            (_measuredMotionSource == motionArtwork?.source &&
                _motionAspectRatio == ratio)) {
          return;
        }
        setState(() {
          _measuredMotionSource = motionArtwork?.source;
          _motionAspectRatio = ratio;
        });
      },
      onError: () {
        if (mounted) {
          setState(() => _failedMotionSource = motionArtwork?.source);
        }
      },
    );

    // The Mornye route moves the entire player together. A second,
    // delayed content fade would make dismissal appear to pause partway down.
    final route = ModalRoute.of(context);
    final routeAnimation = route?.animation ?? kAlwaysCompleteAnimation;
    if (_artworkRoute != route) {
      _artworkRoute?.readArtwork = null;
      _artworkRoute = null;
    }
    if (mornye && route is NowPlayingRoute) {
      _artworkRoute = route;
      route.readArtwork = () {
        final key = _landscape
            ? _expandedArtworkKey
            : _currentPage != 0
            ? _compactArtworkKey
            : fullBleed
            ? _motionArtworkKey
            : _expandedArtworkKey;
        final box = key.currentContext?.findRenderObject();
        if (box is! RenderBox || !box.attached || !box.hasSize) return null;
        final overlay = route.navigator?.overlay?.context.findRenderObject();
        return (
          bounds: MatrixUtils.transformRect(
            box.getTransformTo(overlay),
            Offset.zero & box.size,
          ),
          fullBleed: key == _motionArtworkKey,
          child: Theme(
            data: MornyeTheme.fromContext(context, brightness: Brightness.dark),
            child: key == _compactArtworkKey
                ? PlayerArtwork(
                    artUri: mediaItem.artUri?.toString(),
                    colorScheme: colorScheme,
                    cacheWidth: PlayerArtwork.transitionCacheWidth(context),
                  )
                : artwork(),
          ),
        );
      };
    }
    final contentOpacity = mornye
        ? kAlwaysCompleteAnimation
        : routeAnimation.drive(
            CurveTween(curve: const Interval(0.4, 1.0, curve: Curves.easeOut)),
          );

    // The embedded desktop player keeps a toolbar for its minimize button,
    // which a route reaches by swiping down instead.
    final double? mornyeToolbarHeight = !mornye
        ? null
        : widget.embedded
        ? 48
        : MediaQuery.orientationOf(context) == Orientation.landscape
        ? 0
        : 36;
    final player = Scaffold(
      backgroundColor: mornye || materialBackdrop
          ? Colors.transparent
          : colorScheme.surface,
      appBar: _FadingAppBar(
        opacity: contentOpacity,
        child: AppBar(
          backgroundColor: mornye || materialBackdrop
              ? Colors.transparent
              : colorScheme.surface,
          foregroundColor: overCover ? Colors.white : colorScheme.onSurface,
          surfaceTintColor: Colors.transparent,
          systemOverlayStyle: mornye || overCover
              ? SystemUiOverlayStyle.light
              : null,
          toolbarHeight: mornyeToolbarHeight ?? kToolbarHeight,
          automaticallyImplyLeading: false,
          title: mornye
              ? MediaQuery.orientationOf(context) == Orientation.landscape ||
                        widget.embedded
                    ? null
                    : IconButton(
                        tooltip: context.l10n.nowPlayingMinimize,
                        onPressed: _minimize,
                        icon: Container(
                          width: 36,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      )
              : Text(
                  context.l10n.nowPlayingTitle,
                  // The app theme's title style carries its own colour.
                  style: overCover
                      ? const TextStyle(color: Colors.white)
                      : null,
                ),
          centerTitle: true,
          leading: mornye && !widget.embedded
              ? null
              : AppIconButton(
                  key: const ValueKey('now-playing-minimize'),
                  tooltip: _minimizeTooltip(context),
                  color: overCover || mornye ? Colors.white : null,
                  icon: const AppIcon(Icons.keyboard_arrow_down),
                  onPressed: _minimize,
                ),
          actions: mornye
              ? null
              : [
                  LinkDevicesButton(color: overCover ? Colors.white : null),
                  AppIconButton(
                    tooltip: context.l10n.nowPlayingUpNext,
                    color: overCover ? Colors.white : null,
                    icon: const AppIcon(Icons.queue_music),
                    onPressed: () => _showQueueSheet(context, colorScheme),
                  ),
                  AppIconButton(
                    color: overCover ? Colors.white : null,
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).moreButtonTooltip,
                    icon: const AppIcon(Icons.more_vert),
                    onPressed: () => _showMoreActions(
                      context: context,
                      mediaItem: mediaItem,
                      source: source,
                      colorScheme: colorScheme,
                    ),
                  ),
                ],
        ),
      ),
      body: FadeTransition(
        opacity: contentOpacity,
        child: SafeArea(
          bottom: homeIndicatorBelowRow == null,
          child: Column(
            children: [
              Expanded(
                child: mornye
                    ? MornyePlayerLayout(
                        mediaItem: mediaItem,
                        metadata: _trackMetadata,
                        seekPreview: _seekPreview,
                        colorScheme: colorScheme,
                        page: _currentPage,
                        motionArtwork: artwork(),
                        artworkAspectRatio: artworkRatio,
                        controlsHeadroom: reservesPlayingOnRow
                            ? _mornyeControlsHeadroom
                            : 0,
                        insetArtwork: !fullBleed,
                        artworkTopInset:
                            MediaQuery.paddingOf(context).top +
                            (widget.embedded ? mornyeToolbarHeight! : 36),
                        artworkKeys: (
                          header: _artworkHeaderKey,
                          controls: _artworkControlsKey,
                          volume: _artworkVolumeKey,
                          expanded: _expandedArtworkKey,
                          compact: _compactArtworkKey,
                        ),
                        artworkForeground: _artworkForeground,
                        onPageChanged: _setMornyePage,
                        onTrackNavigation: _showTrackNavigationMenu,
                        onMoreActions: (buttonContext, item, anchor) =>
                            _showMoreActions(
                              context: buttonContext,
                              mediaItem: item,
                              source: item.extras?['source']?.toString() ?? '',
                              colorScheme: colorScheme,
                              anchor: anchor,
                            ),
                      )
                    : MaterialPlayerLayout(
                        mediaItem: mediaItem,
                        metadata: _trackMetadata,
                        seekPreview: _seekPreview,
                        colorScheme: colorScheme,
                        fullScreenArtwork: materialFullScreen,
                        onOpenQueue: () =>
                            _showQueueSheet(context, colorScheme),
                      ),
              ),
              PlayerQueueSwipeRegion(
                onOpenQueue: () => _showQueueSheet(context, colorScheme),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (mornye && !_landscape)
                      FractionallySizedBox(
                        widthFactor: 0.72,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            AudioOutputButton(color: Colors.white),
                            // The row spreads its buttons apart, so the
                            // Devices entry only takes a slot when paired.
                            if (ref.watch(linkPhoneClientProvider) != null)
                              const LinkDevicesButton(color: Colors.white),
                            IconButton(
                              tooltip: context.l10n.nowPlayingUpNext,
                              color: Colors.white,
                              isSelected: _showsPage(1),
                              style: IconButton.styleFrom(
                                backgroundColor: _showsPage(1)
                                    ? Colors.white.withValues(alpha: 0.16)
                                    : Colors.transparent,
                              ),
                              icon: const AppIcon(CupertinoIcons.list_bullet),
                              onPressed: () =>
                                  _setMornyePage(_currentPage == 1 ? 0 : 1),
                            ),
                          ],
                        ),
                      )
                    else if (!mornye)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Filled pills like the shuffle and repeat
                            // segments between them.
                            PlayerPlaybackModeToolbar(colorScheme: colorScheme),
                            AudioOutputButton(
                              color: colorScheme.onSurfaceVariant,
                              backgroundColor: colorScheme.surfaceContainerHigh,
                              width: PlayerPlaybackModeToolbar.segmentWidth,
                            ),
                          ],
                        ),
                      ),
                    // Landscape has no row to spare; the toolbar's devices
                    // button shows the device there.
                    if (MediaQuery.orientationOf(context) ==
                        Orientation.portrait) ...[
                      if (!reservesPlayingOnRow) ...[
                        LinkPlayingOnLabel(color: mornye ? Colors.white : null),
                        const SizedBox(height: 8),
                      ] else
                        SizedBox(
                          key: const ValueKey('link-playing-on-row'),
                          height: _playingOnRowHeight,
                          child: Center(
                            child: LinkPlayingOnLabel(
                              color: mornye ? Colors.white : null,
                              height: _playingOnRowHeight,
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
              if (homeIndicatorBelowRow != null)
                SizedBox(height: homeIndicatorBelowRow),
            ],
          ),
        ),
      ),
    );
    if (!mornye) {
      if (!materialBackdrop) return player;
      return Stack(
        fit: StackFit.expand,
        children: [
          MaterialPlayerBackdrop(
            mediaItem: mediaItem,
            colorScheme: colorScheme,
            showArtwork: materialFullScreen,
          ),
          player,
        ],
      );
    }
    return HeroMode(
      // A route Hero renders outside the panel's gradient and slide, briefly
      // exposing a detached rectangle. Keep Mornye artwork inside its panel.
      enabled: false,
      child: Theme(
        data: MornyeTheme.fromContext(context, brightness: Brightness.dark),
        child: Stack(
          fit: StackFit.expand,
          children: [
            MornyeArtworkContrast(
              enabled: fullBleed && !_landscape && _currentPage == 0,
              continuous: motionArtwork != null,
              targets: {
                'header': _artworkHeaderKey,
                'controls': _artworkControlsKey,
                'volume': _artworkVolumeKey,
              },
              onChanged: (colors) {
                if (!mounted) return;
                _artworkForeground.value = colors;
              },
              child: MornyePlayerBackground(
                artUri: mediaItem.artUri,
                squareArtwork: squareArtwork,
                artworkAspectRatio: artworkRatio,
                fadeStart: stillFullBleed ? 0.72 : 0.58,
                artwork: fullBleed && !_landscape && _currentPage == 0
                    ? PlayerTransitionArtwork(
                        artworkKey: _motionArtworkKey,
                        child: Hero(
                          tag: kNowPlayingArtworkHeroTag,
                          child: artwork(),
                        ),
                      )
                    : null,
              ),
            ),
            player,
          ],
        ),
      ),
    );
  }

  void _setMornyePage(int page) {
    if (_toggleInspector(page)) return;
    setState(() => _currentPage = page);
  }

  Future<void> _openExternally(String source) async {
    if (source.isEmpty) return;
    try {
      await openFile(source);
    } catch (e) {
      if (!mounted) return;
      showCannotOpenFileSnackBar(context, e);
    }
  }

  Future<void> _showTrackNavigationMenu(
    BuildContext titleContext,
    MediaItem mediaItem,
  ) async {
    final action = await showMornyeContextMenu<String>(
      context: titleContext,
      preferAbove: true,
      maxWidth: 280,
      builder: (_) => MornyePlayerNavigationMenu(mediaItem: mediaItem),
    );
    if (!mounted) return;
    if (action == 'album') {
      await _goToCurrentAlbum(
        mediaItem: mediaItem,
        source: mediaItem.extras?['source']?.toString() ?? '',
      );
    } else if (action == 'artist') {
      await _goToCurrentArtist(mediaItem);
    }
  }

  Future<void> _goToCurrentArtist(MediaItem mediaItem) =>
      openPlayingArtist(context, ref, mediaItem);

  Future<void> _updatePlayerCollection(
    MediaItem item, {
    required bool favorite,
  }) async {
    try {
      final provider = playerCollectionTrackProvider(item);
      if (ref.read(provider).hasError) ref.invalidate(provider);
      final track = await ref.read(provider.future);
      if (!mounted) return;
      if (favorite) {
        await ref.read(libraryCollectionsProvider.notifier).toggleLoved(track);
      } else {
        await showAddTrackToPlaylistSheet(context, ref, track);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.snackbarError(context.friendlyError(error)),
          ),
        ),
      );
    }
  }

  Future<void> _showMoreActions({
    required BuildContext context,
    required MediaItem mediaItem,
    required String source,
    required ColorScheme colorScheme,
    Rect? anchor,
  }) async {
    final controller = ref.read(musicPlayerControllerProvider);
    final sleepTimerEndsAt = controller.sleepTimerEndsAt;
    final sleepTimerSubtitle = sleepTimerEndsAt == null
        ? null
        : context.l10n.nowPlayingSleepTimerActive(
            MaterialLocalizations.of(
              context,
            ).formatTimeOfDay(TimeOfDay.fromDateTime(sleepTimerEndsAt)),
          );
    final volumeShown = ref.read(settingsProvider).playerShowVolume;
    final linkClient = ref.read(linkPhoneClientProvider);
    final transfer = await linkTransferSongsOfPlaying(
      ref,
      mediaId: mediaItem.id,
      source: source,
    );
    if (!mounted || !context.mounted) return;
    final sendToDesktop = transfer.phone.isEmpty || linkClient == null
        ? null
        : linkDesktopName(linkClient);
    final saveToPhone = transfer.desktop.isNotEmpty;
    final action = context.isMornye
        ? await showMornyeContextMenu<String>(
            context: context,
            anchor: anchor,
            preferAbove: true,
            maxWidth: 280,
            builder: (_) => MornyePlayerActionsSheet(
              mediaItem: mediaItem,
              sleepTimerSubtitle: sleepTimerSubtitle,
              volumeShown: volumeShown,
              sendToDesktop: sendToDesktop,
              saveToPhone: saveToPhone,
            ),
          )
        : await showAppBottomSheet<String>(
            context: context,
            useRootNavigator: true,
            backgroundColor: colorScheme.surfaceContainerHigh,
            title: mediaItem.title,
            subtitle: mediaItem.artist,
            builder: (sheetContext) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: SettingsGroup(
                children: [
                  if ((mediaItem.album ?? '').trim().isNotEmpty)
                    SettingsItem(
                      icon: Icons.album_outlined,
                      title: sheetContext.l10n.homeGoToAlbum,
                      onTap: () => Navigator.of(sheetContext).pop('album'),
                    ),
                  SettingsItem(
                    icon: Icons.info_outline,
                    title: sheetContext.l10n.nowPlayingDetails,
                    onTap: () => Navigator.of(sheetContext).pop('details'),
                  ),
                  if (sendToDesktop != null)
                    SettingsItem(
                      icon: Icons.computer,
                      title: sheetContext.l10n.linkSendToDesktop(sendToDesktop),
                      onTap: () => Navigator.of(sheetContext).pop('linkSend'),
                    ),
                  if (saveToPhone)
                    SettingsItem(
                      icon: Icons.phone_android,
                      title: sheetContext.l10n.linkSaveToPhone,
                      onTap: () => Navigator.of(sheetContext).pop('linkSave'),
                    ),
                  if (!saveToPhone && canSaveNetworkOfflineSource(source))
                    SettingsItem(
                      icon: Icons.download_for_offline_outlined,
                      title: sheetContext.l10n.offlineSave,
                      onTap: () =>
                          Navigator.of(sheetContext).pop('networkOffline'),
                    ),
                  SettingsItem(
                    icon: Icons.bedtime_outlined,
                    title: sheetContext.l10n.nowPlayingSleepTimer,
                    subtitle: sleepTimerSubtitle,
                    onTap: () => Navigator.of(sheetContext).pop('sleepTimer'),
                  ),
                  SettingsItem(
                    icon: Icons.equalizer,
                    title: sheetContext.l10n.equalizerTitle,
                    onTap: () => Navigator.of(sheetContext).pop('equalizer'),
                  ),
                  SettingsItem(
                    icon: volumeShown
                        ? Icons.volume_off_outlined
                        : Icons.volume_up_outlined,
                    title: volumeShown
                        ? sheetContext.l10n.nowPlayingHideVolume
                        : sheetContext.l10n.nowPlayingShowVolume,
                    onTap: () => Navigator.of(sheetContext).pop('volume'),
                  ),
                  SettingsItem(
                    icon: Icons.open_in_new,
                    title: sheetContext.l10n.nowPlayingOpenInExternalPlayer,
                    trailing: AppIcon(
                      Icons.open_in_new,
                      size: 18,
                      color: Theme.of(
                        sheetContext,
                      ).colorScheme.onSurfaceVariant,
                    ),
                    showDivider: false,
                    onTap: () => Navigator.of(sheetContext).pop('external'),
                  ),
                ],
              ),
            ),
          );
    if (!mounted || !context.mounted) return;
    switch (action) {
      case 'favorite':
        await _updatePlayerCollection(mediaItem, favorite: true);
        break;
      case 'playlist':
        await _updatePlayerCollection(mediaItem, favorite: false);
        break;
      case 'artist':
        await _goToCurrentArtist(mediaItem);
        break;
      case 'share':
        await SharePlus.instance.share(
          ShareParams(
            text: '${mediaItem.title} — ${mediaItem.artist ?? ''}',
            sharePositionOrigin:
                anchor ??
                Rect.fromCenter(
                  center: MediaQuery.sizeOf(context).center(Offset.zero),
                  width: 1,
                  height: 1,
                ),
          ),
        );
        break;
      case 'album':
        await _goToCurrentAlbum(mediaItem: mediaItem, source: source);
        break;
      case 'linkSend':
        await linkSendSongsToDesktop(context, ref, transfer.phone);
        break;
      case 'linkSave':
        linkSaveSongsToPhone(context, ref, transfer.desktop);
        break;
      case 'networkOffline':
        await savePlayingNetworkOffline(context, ref, mediaItem);
        break;
      case 'details':
        unawaited(
          showPlayerDetailsSheet(
            context,
            colorScheme,
            metadata: _trackMetadata,
            mediaItem: ref.read(currentMediaItemProvider).value,
          ),
        );
        break;
      case 'sleepTimer':
        await _showSleepTimerSheet(context, controller, colorScheme);
        break;
      case 'equalizer':
        await pushPage<void>(context, (_) => const EqualizerScreen());
        break;
      case 'volume':
        ref.read(settingsProvider.notifier).setPlayerShowVolume(!volumeShown);
        break;
      case 'external':
        await _openExternally(source);
        break;
    }
  }

  Future<void> _showSleepTimerSheet(
    BuildContext context,
    MusicPlayerController controller,
    ColorScheme colorScheme,
  ) async {
    const durations = [15, 30, 45, 60];
    final isActive = controller.sleepTimerEndsAt != null;
    final selection = await showAppBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      backgroundColor: colorScheme.surfaceContainerHigh,
      title: context.l10n.nowPlayingSleepTimer,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: SettingsGroup(
          children: [
            for (final minutes in durations)
              SettingsItem(
                icon: Icons.timer_outlined,
                title: sheetContext.l10n.nowPlayingSleepTimerMinutes(minutes),
                showDivider: isActive || minutes != durations.last,
                onTap: () => Navigator.of(sheetContext).pop('$minutes'),
              ),
            if (isActive)
              SettingsItem(
                icon: Icons.timer_off_outlined,
                title: sheetContext.l10n.nowPlayingSleepTimerOff,
                showDivider: false,
                onTap: () => Navigator.of(sheetContext).pop('off'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || !context.mounted || selection == null) return;

    if (selection == 'off') {
      controller.cancelSleepTimer();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.nowPlayingSleepTimerCancelled)),
      );
      return;
    }

    final minutes = int.tryParse(selection);
    if (minutes == null) return;
    controller.setSleepTimer(Duration(minutes: minutes));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.l10n.nowPlayingSleepTimerSet(
            context.l10n.nowPlayingSleepTimerMinutes(minutes),
          ),
        ),
      ),
    );
  }

  Future<void> _goToCurrentAlbum({
    required MediaItem mediaItem,
    required String source,
  }) => openPlayingAlbum(context, ref, mediaItem: mediaItem, source: source);

  /// Opens Up Next. The Material sheet captures the theme of [context], the
  /// player's artwork scope.
  void _showQueueSheet(BuildContext context, ColorScheme colorScheme) {
    if (_toggleInspector(2)) return;
    if (context.isMornye) {
      _setMornyePage(2);
      return;
    }
    if (_queueSheetShowing) return;
    _queueSheetShowing = true;
    showPlayerQueueSheet(
      context,
      colorScheme,
    ).whenComplete(() => _queueSheetShowing = false);
  }
}
