import 'package:flutter/foundation.dart';
import '../media/media_item.dart';
import '../media/play_queue.dart';
import '../mixins/disposable_change_notifier_mixin.dart';

/// Result of trying to locate the current queue index.
class _IndexLookupResult {
  final int? index;
  final bool attemptedLoad;
  final bool loadFailed;

  const _IndexLookupResult({this.index, this.attemptedLoad = false, this.loadFailed = false});
}

/// Manages playback state using Plex's play queue API.
/// This provider is session-only and does not persist across app restarts.
class PlaybackStateProvider with ChangeNotifier, DisposableChangeNotifierMixin {
  // Play queue state
  int? _playQueueId;
  int _playQueueTotalCount = 0;
  bool _playQueueShuffled = false;
  int? _currentPlayQueueItemID;

  // Windowed items (loaded around current position)
  List<MediaItem> _loadedItems = [];
  final int _windowSize = 50; // Number of items to keep in memory

  /// Synthetic per-item queue IDs for client-side queues (Jellyfin, etc.).
  /// Parallel to [_loadedItems] — `_syntheticIds[i]` is the queue ID for
  /// `_loadedItems[i]`. Empty when the queue is server-side (Plex), where
  /// the real id lives on [PlexMediaItem.playQueueItemId].
  List<int> _syntheticIds = const [];

  String? _contextKey; // The show/season/playlist ratingKey for this session
  bool _isQueueMode = false;

  /// Returns the queue id for [item] within the current queue. For client-side queues
  /// (Jellyfin) it's a synthetic index assigned in [setPlaybackFromLocalQueue].
  /// Returns null when [item] isn't in the current loaded window.
  int? playQueueItemIdFor(MediaItem item) {
    final idx = _loadedItems.indexOf(item);
    if (idx < 0 || idx >= _syntheticIds.length) return null;
    return _syntheticIds[idx];
  }

  /// Whether shuffle mode is currently active
  bool get isShuffleActive => _playQueueShuffled;

  /// Whether playlist/collection mode is currently active
  bool get isPlaylistActive => _isQueueMode;

  /// Whether any queue-based playback is active
  bool get isQueueActive => _playQueueId != null && _isQueueMode;

  /// Whether [item] belongs to the currently active queue. True for
  /// items present in a Jellyfin local queue (synthetic id). Membership for
  /// local queues is by object identity — [MediaItem] is `@Freezed(equal:
  /// false)` — so only the exact instances stored in the queue match.
  /// Gates the player's "preserve vs. wipe launcher-set queue" decision in
  /// [VideoPlayerScreen.initState], `_ensurePlayQueue`, and
  /// [EpisodeNavigationService]'s `_ensureLocalEpisodeQueue`, so a
  /// playlist, collection, or shuffled show queue survives entry into the
  /// player instead of being replaced with a sequential show queue.
  bool isItemInActiveQueue(MediaItem item) => isQueueActive && playQueueItemIdFor(item) != null;

  /// The context key (show/season/playlist ratingKey) for the current session
  String? get shuffleContextKey => _contextKey;

  /// Current play queue ID
  int? get playQueueId => _playQueueId;

  /// The currently loaded queue items (windowed subset of full queue)
  List<MediaItem> get loadedItems => List.unmodifiable(_loadedItems);

  /// The current play queue item ID
  int? get currentPlayQueueItemID => _currentPlayQueueItemID;

  /// The queue item the cursor currently points at, or null when no queue
  /// is active or the cursor is outside the loaded window.
  MediaItem? get currentQueueItem =>
      _currentPlayQueueItemID == null ? null : _findLoadedItem(_currentPlayQueueItemID!);

  /// Update the current play queue item when playing a new item
  void setCurrentItem(MediaItem metadata) {
    if (!_isQueueMode) return;
    final id = playQueueItemIdFor(metadata);
    if (id != null) {
      _currentPlayQueueItemID = id;
      safeNotifyListeners();
    }
  }

  /// Initialize playback from a [LocalPlayQueue] (Jellyfin / any backend
  /// without a server-side queue). Synthetic per-item queue IDs are
  /// recorded in [_syntheticIds] (parallel to [_loadedItems]) so the
  /// existing Plex-shaped UI — Queue sheet, content strip, current item
  /// highlight — keeps working without a parallel rendering path. Items
  /// themselves are stored unmutated.
  ///
  /// `playQueueId` is set to a sentinel so [isQueueActive] returns true.
  void setPlaybackFromLocalQueue(LocalPlayQueue queue, {String? contextKey}) {
    _playQueueId = -1; // sentinel for "client-side queue"
    _playQueueTotalCount = queue.items.length;
    _playQueueShuffled = queue.shuffled;
    _loadedItems = List.of(queue.items);
    _syntheticIds = [for (var i = 0; i < queue.items.length; i++) i];
    _currentPlayQueueItemID = queue.currentIndex;
    _contextKey = contextKey;
    _isQueueMode = true;
    safeNotifyListeners();
  }

  /// Load more items from the play queue if needed
  /// Returns true if more items were loaded
  Future<bool> _ensureItemsLoaded(int targetPlayQueueItemID) async {
    return false;
  }

  Future<_IndexLookupResult> _getCurrentIndex({bool loadIfMissing = false}) async {
    if (!_isQueueMode || _loadedItems.isEmpty || _currentPlayQueueItemID == null) {
      return const _IndexLookupResult();
    }

    var currentIndex = _findLoadedIndex(_currentPlayQueueItemID!);

    if (currentIndex != -1) {
      return _IndexLookupResult(index: currentIndex);
    }

    if (!loadIfMissing || _playQueueId == null) {
      return const _IndexLookupResult();
    }

    final loaded = await _ensureItemsLoaded(_currentPlayQueueItemID!);
    if (!loaded) {
      return const _IndexLookupResult(attemptedLoad: true, loadFailed: true);
    }

    currentIndex = _findLoadedIndex(_currentPlayQueueItemID!);

    if (currentIndex == -1) {
      return const _IndexLookupResult(attemptedLoad: true, loadFailed: true);
    }

    return _IndexLookupResult(index: currentIndex, attemptedLoad: true);
  }

  /// Returns the index of the item with [playQueueItemId] in [_loadedItems],
  /// or -1 if absent. Bridges Plex (real id on [PlexMediaItem]) and
  /// client-side (synthetic id in [_syntheticIds]) queues.
  int _findLoadedIndex(int playQueueItemId) {
    for (var i = 0; i < _loadedItems.length; i++) {
      if (i < _syntheticIds.length && _syntheticIds[i] == playQueueItemId) {
        return i;
      }
    }
    return -1;
  }

  MediaItem? _findLoadedItem(int playQueueItemId) {
    final index = _findLoadedIndex(playQueueItemId);
    return index == -1 ? null : _loadedItems[index];
  }

  /// Gets the next item in the playback queue.
  /// Returns null if queue is exhausted or current item is not in queue.
  /// [loopQueue] - If true, restart from beginning when queue is exhausted
  Future<MediaItem?> getNextEpisode(String currentItemKey, {bool loopQueue = false}) async {
    if (!_isQueueMode) {
      // For sequential mode, let the video player handle next episode
      return null;
    }

    final indexResult = await _getCurrentIndex(loadIfMissing: true);
    if (indexResult.index == null) {
      if (indexResult.loadFailed) {
        clearShuffle();
      }
      return null;
    }
    final currentIndex = indexResult.index!;

    // Check if there's a next item in the loaded window
    if (currentIndex + 1 < _loadedItems.length) {
      // Don't update _currentPlayQueueItemID here - let setCurrentItem do it when playback starts
      return _loadedItems[currentIndex + 1];
    }

    // Check if we're at the end of the entire queue
    if (currentIndex + 1 >= _playQueueTotalCount) {
      // At end of queue - return null but keep queue active so user can still go back
      return null;
    }

    return null;
  }

  /// Gets the previous item in the playback queue.
  /// Returns null if at the beginning of the queue or current item is not in queue.
  Future<MediaItem?> getPreviousEpisode(String currentItemKey) async {
    if (!_isQueueMode) {
      // For sequential mode, let the video player handle previous episode
      return null;
    }

    final currentIndex = (await _getCurrentIndex()).index;
    if (currentIndex == null) return null;

    // Check if there's a previous item in the loaded window
    if (currentIndex > 0) {
      // Don't update _currentPlayQueueItemID here - let setCurrentItem do it when playback starts
      return _loadedItems[currentIndex - 1];
    }

    // Check if we're at the beginning of the entire queue
    if (currentIndex == 0) {
      return null;
    }

    return null;
  }

  /// Clears the playback queue and exits queue mode
  void clearShuffle() {
    _playQueueId = null;
    _playQueueTotalCount = 0;
    _playQueueShuffled = false;
    _currentPlayQueueItemID = null;
    _loadedItems = [];
    _syntheticIds = const [];
    _contextKey = null;
    _isQueueMode = false;
    safeNotifyListeners();
  }
}
