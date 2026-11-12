import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mornye/l10n/l10n.dart';
import 'package:mornye/models/download_history.dart';
import 'package:mornye/models/library_database_models.dart';
import 'package:mornye/models/unified_library_item.dart';
import 'package:mornye/providers/download_history_provider.dart';
import 'package:mornye/providers/local_library_provider.dart';
import 'package:mornye/screens/track_metadata_edit_sheet.dart';
import 'package:mornye/services/library_database.dart';
import 'package:mornye/services/playback_metadata.dart';
import 'package:mornye/services/source_metadata_events.dart';
import 'package:mornye/utils/file_access.dart';
import 'package:mornye/utils/string_utils.dart';
import 'package:mornye/widgets/app_bottom_sheet.dart';

/// Whether the library's context menu can offer the tag editor for [item]:
/// a single song backed by a local file the editor can open and write.
bool canEditTrackTags(UnifiedLibraryItem item) {
  final path = item.filePath;
  if (path.startsWith('network://') ||
      path.startsWith('content://') ||
      isCueVirtualPath(path)) {
    return false;
  }
  try {
    return File(path).existsSync();
  } on Object {
    return false;
  }
}

/// Opens the tag editor for a single library song from a context menu.
///
/// The file's tags load with a short timeout; a failed or hung read still
/// opens the editor over the library's values, so the editor is always
/// reachable. Saving writes the file through the shared persistence service,
/// whose event refreshes every surface that shows the song.
Future<void> showTrackTagEditor(
  BuildContext context,
  WidgetRef ref,
  UnifiedLibraryItem item,
) async {
  final filePath = item.filePath;
  Map<String, dynamic>? fileMetadata;
  try {
    final result = await readPlaybackFileMetadataWithRetry(
      filePath,
    ).timeout(const Duration(seconds: 4));
    if (result['error'] == null) fileMetadata = result;
  } on Object {
    // The library's values stand in below.
  }
  if (!context.mounted) return;

  String val(String key, String? fallback) =>
      fileMetadata?[key]?.toString() ?? fallback ?? '';

  final local = item.localItem;
  final history = item.historyItem;
  final saved = await showAppModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    dialogSize: AppDialogSize.wide,
    builder: (sheetContext) => EditMetadataSheet(
      colorScheme: Theme.of(sheetContext).colorScheme,
      initialValues: {
        'title': val('title', item.trackName),
        'artist': val('artist', item.artistName),
        'album': val('album', item.albumName),
        'album_artist': val('album_artist', local?.albumArtist),
        'date': val('date', local?.releaseDate),
        'track_number': val('track_number', local?.trackNumber?.toString()),
        'total_tracks': val('total_tracks', local?.totalTracks?.toString()),
        'disc_number': val('disc_number', local?.discNumber?.toString()),
        'total_discs': val('total_discs', local?.totalDiscs?.toString()),
        'genre': val('genre', local?.genre),
        'isrc': val('isrc', local?.isrc),
        'label': val('label', local?.label),
        'copyright': val('copyright', local?.copyright),
        'composer': val('composer', local?.composer),
        'comment': val('comment', null),
        'album_type': val('album_type', null),
        'explicit': (parseExplicitFlag(fileMetadata?['explicit']) ?? false)
            ? '1'
            : '0',
        'upc': val('upc', null),
        'lyrics': val('lyrics', null),
      },
      filePath: filePath,
      durationMs: (local?.duration ?? 0) * 1000,
      artistTagMode: 'all',
    ),
  );
  if (saved != true || !context.mounted) return;

  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(context.l10n.snackbarMetadataSaved)));
  await _refreshStoredTrack(ref, item, local: local, history: history);
}

/// Reads the saved tags back into the row the library shows.
Future<void> _refreshStoredTrack(
  WidgetRef ref,
  UnifiedLibraryItem item, {
  required LocalLibraryItem? local,
  required DownloadHistoryItem? history,
}) async {
  Map<String, dynamic>? metadata;
  try {
    final result = await readPlaybackFileMetadataWithRetry(
      item.filePath,
    ).timeout(const Duration(seconds: 4));
    if (result['error'] == null) metadata = result;
  } on Object {
    return;
  }
  if (metadata == null) return;
  // A closure cannot promote the captured map, so pin the non-null value.
  final data = metadata;
  String? text(String key) => switch (data[key]) {
    final String value? => value,
    _ => null,
  };
  final name = text('title') ?? item.trackName;
  final artist = text('artist') ?? item.artistName;
  final album = text('album') ?? item.albumName;

  if (history != null) {
    await ref
        .read(downloadHistoryProvider.notifier)
        .updateMetadataForItem(
          id: history.id,
          trackName: name,
          artistName: artist,
          albumName: album,
          albumArtist: text('album_artist'),
          releaseDate: text('date'),
          genre: text('genre'),
          composer: text('composer'),
          label: text('label'),
          copyright: text('copyright'),
          isrc: text('isrc'),
        );
  }
  if (local != null) {
    final row = local.toJson()
      ..addAll({
        'trackName': name,
        'artistName': artist,
        'albumName': album,
        'albumArtist': text('album_artist'),
        'releaseDate': text('date'),
        'genre': text('genre'),
        'composer': text('composer'),
        'label': text('label'),
        'copyright': text('copyright'),
        'isrc': text('isrc'),
      });
    await LibraryDatabase.instance.upsertBatchExcludingHistory([
      row,
    ], sourceId: local.sourceId);
    unawaited(SourceMetadataEvents.instance.publish(item.filePath));
    await ref.read(localLibraryProvider.notifier).reloadFromStorage();
  }
}
