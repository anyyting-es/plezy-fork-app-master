part of '../../video_player_screen.dart';

extension _VideoPlayerEpisodeQueueMethods on VideoPlayerScreenState {
  Future<void> _ensurePlayQueue() async {
    // Server-side play queues are no longer supported
  }

  Future<void> _loadAdjacentEpisodes({MediaItem? metadata, _PlaybackAttempt? attempt}) async {
    if (!mounted || widget.isLive) return;

    final targetMetadata = metadata ?? _currentMetadata;

    if (_offlineLibraryMode) {
      // Offline mode: find next/previous from downloaded episodes
      _loadAdjacentEpisodesOffline();
      return;
    }

    try {
      final adjacentEpisodes = await _episodeNavigation.loadAdjacentEpisodes(
        context: context,
        metadata: targetMetadata,
      );

      if (mounted && _currentMetadata.globalKey == targetMetadata.globalKey && (attempt == null || attempt.isCurrent)) {
        _setPlayerState(() {
          _nextEpisode = adjacentEpisodes.next;
          _previousEpisode = adjacentEpisodes.previous;
        });
      }
    } catch (e) {
      // Non-critical: Failed to load next/previous episode metadata
      appLogger.d('Could not load adjacent episodes', error: e);
    }
  }

  /// Load next/previous episodes from locally downloaded content
  void _loadAdjacentEpisodesOffline() {
    if (!_currentMetadata.isEpisode) return;

    final showKey = _currentMetadata.grandparentId;
    if (showKey == null) return;

    try {
      final downloadProvider = context.read<DownloadProvider>();
      final episodes = downloadProvider.getDownloadedEpisodesForShow(showKey);

      if (episodes.isEmpty) return;

      // Aired watch order (Specials interleaved by air date) — the shared
      // episode order, so offline next/prev matches streaming, what "download
      // next N" selects, and the offline OnDeck list (#1416/#1414). Copy first
      // so the provider's cached list isn't reordered.
      final sorted = List<MediaItem>.from(episodes)..sort(compareEpisodesByWatchOrder);

      final currentIdx = sorted.indexWhere((ep) => ep.id == _currentMetadata.id);

      if (currentIdx == -1) return;

      if (mounted) {
        _setPlayerState(() {
          _previousEpisode = currentIdx > 0 ? sorted[currentIdx - 1] : null;
          _nextEpisode = currentIdx < sorted.length - 1 ? sorted[currentIdx + 1] : null;
        });
      }
    } catch (e) {
      appLogger.d('Could not load offline adjacent episodes', error: e);
    }
  }
}
