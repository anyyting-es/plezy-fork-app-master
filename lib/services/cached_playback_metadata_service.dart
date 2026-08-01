import 'dart:async';
import '../media/ids.dart';
import '../media/media_backend.dart';
import '../media/media_source_info.dart';

class CachedPlaybackMetadataService {
  const CachedPlaybackMetadataService._();

  static Future<MediaSourceInfo?> fetchMediaSourceInfo({
    required MediaBackend backend,
    required String cacheServerId,
    required String itemId,
    int mediaIndex = 0,
  }) async {
    return null;
  }

  static Future<PlaybackExtras?> fetchPlaybackExtras({
    required MediaBackend backend,
    required String cacheServerId,
    required String itemId,
    String? introPattern,
    String? creditsPattern,
    bool forceChapterFallback = false,
  }) async {
    return null;
  }
}
