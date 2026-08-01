import 'dart:async';
import 'package:flutter/material.dart';
import '../media/media_item.dart';

sealed class PlayQueueResult {
  const PlayQueueResult();
}

class PlayQueueSuccess extends PlayQueueResult {
  const PlayQueueSuccess();
}

class PlayQueueEmpty extends PlayQueueResult {
  const PlayQueueEmpty();
}

class PlayQueueError extends PlayQueueResult {
  final Object error;
  const PlayQueueError(this.error);
}

abstract class MediaListPlaybackLauncher {
  Future<PlayQueueResult> launchFromCollectionOrPlaylist({
    required Object item,
    required bool shuffle,
    MediaItem? startItem,
    bool showLoadingIndicator = true,
  });

  Future<PlayQueueResult> launchShuffledShow({required MediaItem metadata, bool showLoadingIndicator = true});

  static MediaListPlaybackLauncher forItem(BuildContext context, Object item) {
    return _MockPlaybackLauncher();
  }

  static dynamic classifyItem(Object item) => null;
}

class _MockPlaybackLauncher extends MediaListPlaybackLauncher {
  _MockPlaybackLauncher();

  @override
  Future<PlayQueueResult> launchFromCollectionOrPlaylist({
    required Object item,
    required bool shuffle,
    MediaItem? startItem,
    bool showLoadingIndicator = true,
  }) async {
    return const PlayQueueSuccess();
  }

  @override
  Future<PlayQueueResult> launchShuffledShow({required MediaItem metadata, bool showLoadingIndicator = true}) async {
    return const PlayQueueSuccess();
  }
}
