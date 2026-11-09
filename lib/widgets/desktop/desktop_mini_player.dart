part of 'desktop_player_bar.dart';

/// Whether the window shows the mini player ([DesktopMiniPlayer]) in place
/// of the shell.
final desktopMiniPlayerOpen = ValueNotifier<bool>(false);

const double _miniPlayerWidth = 360;
const double _miniPlayerHeight = 140;

Size _miniPlayerSize() => const Size(_miniPlayerWidth, _miniPlayerHeight);

/// The content size requested from the native mini player window.
Size get desktopMiniPlayerSize => _miniPlayerSize();

bool _miniPlayerBusy = false;

/// Turns the window into the mini player, or back into the full window.
Future<void> toggleDesktopMiniPlayer() =>
    setDesktopMiniPlayer(open: !desktopMiniPlayerOpen.value);

/// Shrinks the window into a small panel that floats above other windows,
/// or returns it to its full size and place.
Future<void> setDesktopMiniPlayer({required bool open}) async {
  if (!desktopMiniPlayerSupported ||
      _miniPlayerBusy ||
      open == desktopMiniPlayerOpen.value) {
    return;
  }
  _miniPlayerBusy = true;
  try {
    if (open) {
      desktopPlayerDismissed.value = false;
      desktopMiniPlayerOpen.value = true;
      final opened = await openDesktopMiniPlayerWindow(desktopMiniPlayerSize);
      if (!opened) desktopMiniPlayerOpen.value = false;
    } else {
      // The shell fades back with the window's actual size. Keep both
      // surfaces mounted until AppKit finishes restoring the frame.
      await closeDesktopMiniPlayerWindow();
      desktopMiniPlayerOpen.value = false;
    }
  } finally {
    _miniPlayerBusy = false;
  }
}

/// The mini player: the track, the transport and a thin progress bar. The
/// window floats above other apps while it shows; dragging anywhere but a
/// control moves it.
///
/// Material takes the track's artwork scheme on `surfaceContainer`; Mornye
/// uses the dark Now Playing background.
class DesktopMiniPlayer extends ConsumerStatefulWidget {
  const DesktopMiniPlayer({super.key, this.metadataControllerFactory});

  final PlayerMetadataController Function()? metadataControllerFactory;

  @override
  ConsumerState<DesktopMiniPlayer> createState() => _DesktopMiniPlayerState();
}

class _DesktopMiniPlayerState extends ConsumerState<DesktopMiniPlayer> {
  late final _metadata =
      widget.metadataControllerFactory?.call() ?? PlayerMetadataController();
  ProviderSubscription<AsyncValue<MediaItem?>>? _mediaItemSub;

  @override
  void initState() {
    super.initState();
    _mediaItemSub = ref.listenManual<AsyncValue<MediaItem?>>(
      currentMediaItemProvider,
      (previous, next) {
        if (previous?.value?.id == next.value?.id && previous != null) return;
        unawaited(
          _metadata.load(next.value, inspectUnresolvedContentUri: true),
        );
      },
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _mediaItemSub?.close();
    _metadata.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaItem = ref.watch(currentMediaItemProvider).value;
    if (context.isMornye) return _buildPanel(context, mediaItem);
    return PlayerArtworkTheme(
      artUri: mediaItem?.artUri?.toString(),
      child: Builder(builder: (context) => _buildPanel(context, mediaItem)),
    );
  }

  Widget _buildPanel(BuildContext context, MediaItem? mediaItem) {
    final mornye = context.isMornye;
    final theme = mornye
        ? MornyeTheme.fromContext(context, brightness: Brightness.dark)
        : Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Theme(
      data: theme,
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (mornye)
              MornyePlayerBackground(artUri: mediaItem?.artUri)
            else
              ColoredBox(color: colorScheme.surfaceContainer),
            // Behind the content, so empty space and text drag the window
            // while the controls keep their clicks.
            const Positioned.fill(
              child: DesktopWindowDragArea(frameless: true),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: _content(context, mediaItem),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext context, MediaItem? mediaItem) {
    final mornye = context.isMornye;
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final buttonStyle = IconButton.styleFrom(
      minimumSize: const Size.square(36),
      padding: const EdgeInsets.all(6),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 88,
          child: Row(
            children: [
              _Artwork(mediaItem: mediaItem, size: 72, radius: mornye ? 8 : 12),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (mediaItem == null)
                      Text(
                        l10n.desktopPlayerIdle,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    else
                      _TitleAndArtist(mediaItem: mediaItem),
                    _Transport(enabled: mediaItem != null),
                  ],
                ),
              ),
              Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  AppIconButton(
                    key: const ValueKey('desktop-mini-player-expand'),
                    tooltip: desktopTooltip(
                      context,
                      l10n.desktopMiniPlayerExpand,
                      DesktopCommand.miniPlayer,
                    ),
                    iconSize: 20,
                    style: buttonStyle,
                    color: colorScheme.onSurfaceVariant,
                    icon: AppIcon(
                      mornye
                          ? CupertinoIcons.arrow_up_left_arrow_down_right
                          : Icons.open_in_full,
                    ),
                    onPressed: () => setDesktopMiniPlayer(open: false),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // The Material slider keeps its full height for dragging, centered
        // on a thin row.
        SizedBox(
          height: 16,
          child: OverflowBox(
            minHeight: 0,
            maxHeight: mornye ? 10 : 48,
            child: _SeekRow(mediaItem: mediaItem, dense: true),
          ),
        ),
      ],
    );
  }
}
