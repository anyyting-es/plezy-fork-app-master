/// Smart Torrent Download Service
///
/// Searches torrent extensions for the best-matching torrent based on
/// the user's quality / audio / provider preferences, then enqueues it
/// via [TorrentEngineService].
library;

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/plugin_extensions_service.dart';
import '../services/torrent_engine_service.dart';
import '../services/torrent_metadata_service.dart';
import '../media/media_item.dart';
import '../media/media_item_types.dart';
import '../media/media_kind.dart';
import '../anime/services/anizip_service.dart';
import '../services/settings_service.dart';
import '../utils/app_logger.dart';
import 'smart_download_config.dart';

// ---------------------------------------------------------------------------
// Result reported back to the UI
// ---------------------------------------------------------------------------
class SmartDownloadResult {
  final bool success;
  final String? torrentName;
  final String? errorMessage;

  const SmartDownloadResult({
    required this.success,
    this.torrentName,
    this.errorMessage,
  });
}

// ---------------------------------------------------------------------------
// Progress callback so the dialog can show status text
// ---------------------------------------------------------------------------
typedef SmartDownloadProgressCallback = void Function(String status);

// ---------------------------------------------------------------------------
// Core service
// ---------------------------------------------------------------------------
class SmartTorrentDownloadService {
  SmartTorrentDownloadService._();
  static final instance = SmartTorrentDownloadService._();

  // Expose public search method
  Future<List<Map<String, dynamic>>> searchTorrents({
    required MediaItem metadata,
    required String query,
    required bool isMovie,
    bool isBatch = false,
  }) async {
    return _searchTorrents(
      query: query,
      isMovie: isMovie,
      isBatch: isBatch,
      metadata: metadata,
    );
  }

  // Scrape a specific provider
  Future<List<Map<String, dynamic>>> searchTorrentsOnProvider({
    required String providerId,
    required String query,
    required bool isMovie,
    required MediaItem metadata,
  }) async {
    final allResults = <Map<String, dynamic>>[];
    try {
      final engineUrl = TorrentEngineService.instance.baseUrl;
      final backendBase = engineUrl.isNotEmpty ? engineUrl : 'http://127.0.0.1:9876';

      final searchUrl = Uri.parse(
        '$backendBase/extensions/search?provider=$providerId&query=${Uri.encodeComponent(query)}',
      );
      final response = await http.get(searchUrl).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final list = jsonDecode(response.body) as List;
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            allResults.add({...item, '_provider': providerId});
          }
        }
      }
    } catch (e) {
      appLogger.d('[SmartDownload] Search via $providerId failed: $e');
    }
    return allResults;
  }

  // Expose public enqueue method
  Future<SmartDownloadResult> enqueueTorrent(Map<String, dynamic> torrent, MediaItem metadata) async {
    return _enqueueTorrent(torrent, metadata);
  }

  // Extract Anilist ID public helper
  int? extractAnilistId(MediaItem metadata) {
    if (metadata.id.startsWith('anime_ep_')) {
      final parts = metadata.id.split('_');
      if (parts.length > 2) return int.tryParse(parts[2]);
    }
    if (metadata.id.startsWith('anime_')) {
      final parts = metadata.id.split('_');
      if (parts.length > 1) return int.tryParse(parts[1]);
    }
    if (metadata.grandparentId != null && metadata.grandparentId!.startsWith('anime_')) {
      final parts = metadata.grandparentId!.split('_');
      if (parts.length > 1) return int.tryParse(parts[1]);
    }
    return null;
  }

  // Replace episode number in title
  String? replaceEpisodeNumber(String title, int selectedEp, int targetEp) {
    final patterns = [
      RegExp(r'[Ss]\d{1,2}[\s\-_.]?[Ee](\d{1,4})'),
      RegExp(r'\b\d{1,2}x(\d{1,4})\b'),
      RegExp(r'[Ee][Pp]?[\s\-]?(\d+)'),
      RegExp(r'[\s\[\(-](\d+)[\s\]\)-]'),
      RegExp(r'[\s\-]+(\d+)[\s]+'),
      RegExp(r'[\s\[\(-](\d+)v[\s\[\]-]'),
    ];

    for (final pattern in patterns) {
      final matches = pattern.allMatches(title);
      for (final match in matches) {
        final grp = match.group(1);
        if (grp != null) {
          final parsed = int.tryParse(grp);
          if (parsed == selectedEp) {
            // Avoid matching resolution or year if pattern is generic
            if (pattern.pattern.contains(r'[\s') && (parsed == 1080 || parsed == 720 || parsed == 2024 || parsed == 2025 || parsed == 2026)) {
              continue;
            }
            final start = match.start + match.group(0)!.indexOf(grp);
            final end = start + grp.length;
            final paddedTarget = targetEp.toString().padLeft(grp.length, '0');
            return title.replaceRange(start, end, paddedTarget);
          }
        }
      }
    }
    return null;
  }

  // Check if two titles match except for the episode number and CRC32
  bool titlesMatchExceptEpisode(String selectedTitle, int selectedEp, String candidateTitle, int candidateEp) {
    String clean(String title) {
      var s = title.toLowerCase();
      s = s.replaceAll(RegExp(r'\[[0-9a-f]{8}\]'), '');
      s = s.replaceAll(RegExp(r'\.(mkv|mp4|avi|torrent)$'), '');
      s = s.replaceAll(RegExp(r'[\s\-_\.]+'), ' ');
      return s.trim();
    }

    final cleanSelected = clean(selectedTitle);
    final replacedCandidate = replaceEpisodeNumber(candidateTitle, candidateEp, selectedEp);
    if (replacedCandidate == null) return false;

    final cleanCandidate = clean(replacedCandidate);
    return cleanSelected == cleanCandidate;
  }

  // Clean a title for search query
  String cleanTitleForSearch(String title) {
    var s = title;
    s = s.replaceAll(RegExp(r'\[[a-fA-F0-9]{8}\]'), '');
    s = s.replaceAll(RegExp(r'\.(mkv|mp4|avi|torrent)$', caseSensitive: false), '');
    return s.trim();
  }


  // -------------------------------------------------------------------------
  // Public entry point: download all episodes of a series (or single movie/ep)
  // -------------------------------------------------------------------------
  Future<List<SmartDownloadResult>> downloadMedia({
    required MediaItem metadata,
    required SmartDownloadConfig config,
    SmartDownloadProgressCallback? onProgress,
  }) async {
    final results = <SmartDownloadResult>[];

    if (metadata.isShow || metadata.isSeason) {
      // For series/seasons find per-episode torrents or batch pack
      results.addAll(await _downloadSeries(metadata, config, onProgress));
    } else {
      // Single movie or episode
      results.add(await _downloadSingle(metadata, config, onProgress));
    }

    return results;
  }

  // -------------------------------------------------------------------------
  // Series: try batch-pack first (all episodes in one torrent), then per-ep
  // -------------------------------------------------------------------------
  Future<List<SmartDownloadResult>> _downloadSeries(
    MediaItem metadata,
    SmartDownloadConfig config,
    SmartDownloadProgressCallback? onProgress,
  ) async {
    onProgress?.call('Buscando pack de temporada completa...');

    // Use the show title for batch pack search
    final showTitle = metadata.grandparentTitle ?? metadata.title ?? '';
    final torrents = await _searchTorrents(
      query: showTitle,
      isMovie: false,
      isBatch: true,
      metadata: metadata,
    );

    if (torrents.isEmpty) {
      return [
        const SmartDownloadResult(
          success: false,
          errorMessage: 'No se encontraron torrents para esta serie.',
        ),
      ];
    }

    // Pick the single best torrent for the whole series
    onProgress?.call('Seleccionando mejor torrent...');
    final best = _pickBest(torrents, config);

    if (best == null) {
      return [
        const SmartDownloadResult(
          success: false,
          errorMessage: 'Ningún torrent coincidió con los criterios seleccionados.',
        ),
      ];
    }

    onProgress?.call('Añadiendo a la cola: ${best['title']}');
    final added = await _enqueueTorrent(best, metadata);
    return [added];
  }

  // -------------------------------------------------------------------------
  // Single: episode or movie
  // -------------------------------------------------------------------------
  Future<SmartDownloadResult> _downloadSingle(
    MediaItem metadata,
    SmartDownloadConfig config,
    SmartDownloadProgressCallback? onProgress,
  ) async {
    final isMovie = metadata.kind == MediaKind.movie;
    final title = metadata.grandparentTitle ?? metadata.title ?? '';
    final epNum = metadata.index ?? 1;
    final query = isMovie ? title : '$title ${epNum.toString().padLeft(2, '0')}';

    onProgress?.call('Buscando torrent para: $query...');
    final torrents = await _searchTorrents(
      query: query,
      isMovie: isMovie,
      isBatch: false,
      metadata: metadata,
    );

    if (torrents.isEmpty) {
      return const SmartDownloadResult(
        success: false,
        errorMessage: 'No se encontraron torrents para este contenido.',
      );
    }

    onProgress?.call('Seleccionando mejor torrent...');
    final best = _pickBest(torrents, config);
    if (best == null) {
      return const SmartDownloadResult(
        success: false,
        errorMessage: 'Ningún torrent coincidió con los criterios seleccionados.',
      );
    }

    onProgress?.call('Añadiendo a la cola: ${best['title']}');
    return _enqueueTorrent(best, metadata);
  }

  // -------------------------------------------------------------------------
  // Search torrents via backend extensions
  // -------------------------------------------------------------------------
  Future<List<Map<String, dynamic>>> _searchTorrents({
    required String query,
    required bool isMovie,
    required bool isBatch,
    required MediaItem metadata,
  }) async {
    final allResults = <Map<String, dynamic>>[];

    final extensions = await _getTorrentExtensions(metadata);
    if (extensions.isEmpty) {
      throw 'No hay extensiones habilitadas. Configúralas en Ajustes > Extensiones.';
    }

    try {
      // 1. Try per-extension method calls if AniDB IDs are available
      final anilistId = _extractAnilistId(metadata);

      if (anilistId != null) {
        final anidbAid = AniZipService.getAnidbAid(anilistId);

        if (anidbAid != null && anidbAid > 0) {
          for (final ext in extensions) {
            try {
              final args = isBatch
                  ? [
                      {'anidbAid': anidbAid},
                      {'useTorrent': false},
                    ]
                  : [
                      {
                        'anidbAid': anidbAid,
                        'episode': metadata.index ?? 1,
                      },
                      {'useTorrent': false},
                    ];

              final results = await PluginExtensionsService.callMethod(
                providerId: ext.id,
                method: isBatch ? 'batch' : 'single',
                args: args,
              );

              if (results != null) {
                for (final r in results) {
                  if (r is Map<String, dynamic>) {
                    allResults.add({...r, '_provider': ext.id});
                  }
                }
              }
            } catch (e) {
              appLogger.d('[SmartDownload] Extension ${ext.id} failed: $e');
            }
          }
        }
      }

      // 2. Fallback: text search via backend /extensions/search
      if (allResults.isEmpty) {
        final engineUrl = TorrentEngineService.instance.baseUrl;
        final backendBase = engineUrl.isNotEmpty ? engineUrl : 'http://127.0.0.1:9876';

        for (final ext in extensions) {
          try {
            final searchUrl = Uri.parse(
              '$backendBase/extensions/search?provider=${ext.id}&query=${Uri.encodeComponent(query)}',
            );
            final response = await http.get(searchUrl).timeout(const Duration(seconds: 15));
            if (response.statusCode == 200) {
              final list = jsonDecode(response.body) as List;
              for (final item in list) {
                if (item is Map<String, dynamic>) {
                  allResults.add({...item, '_provider': ext.id});
                }
              }
            }
          } catch (e) {
            appLogger.d('[SmartDownload] Search via ${ext.id} failed: $e');
          }
        }
      }
    } catch (e) {
      appLogger.e('[SmartDownload] Error searching torrents', error: e);
      rethrow;
    }

    return allResults;
  }

  // -------------------------------------------------------------------------
  // Scoring + ranking
  // -------------------------------------------------------------------------
  Map<String, dynamic>? _pickBest(
    List<Map<String, dynamic>> torrents,
    SmartDownloadConfig config,
  ) {
    int score(Map<String, dynamic> torrent) {
      final title = (torrent['title'] as String? ?? '').toLowerCase();
      int s = 0;

      // Seed bonus (up to 50 pts)
      final seeds = (torrent['seeders'] as num?)?.toInt() ?? 0;
      s += (seeds.clamp(0, 5000) / 100).round();

      // Quality match (30 pts)
      if (config.quality != SmartDownloadQuality.any) {
        if (title.contains(config.quality.tag.toLowerCase())) { s += 30; }
      } else {
        // 'Any' — prefer higher quality
        if (title.contains('1080p')) { s += 20; }
        else if (title.contains('720p')) { s += 12; }
        else if (title.contains('480p')) { s += 5; }
      }

      // Provider / release group match (25 pts)
      if (config.provider != SmartDownloadProvider.any) {
        if (title.contains(config.provider.tag.toLowerCase())) { s += 25; }
      }

      // Audio / sub match (20 pts)
      switch (config.audio) {
        case SmartDownloadAudio.dub:
          // 'Dub', 'Dubbed', 'Multi-Audio', 'Dual-Audio' all work
          if (_matchesDub(title)) { s += 20; }
        case SmartDownloadAudio.multiAudio:
          if (title.contains('multi') && title.contains('audio')) { s += 20; }
          else if (title.contains('dual') && title.contains('audio')) { s += 15; }
        case SmartDownloadAudio.multiSub:
          // Explicit 'multi sub' OR implicit: many releases are multi-sub by default
          // (Erai-raws, ToonsHub, SubsPlease ship multi-sub without explicit tag)
          if (_matchesMultiSub(title)) { s += 20; }
          else { s += 5; } // still useful, might be unlabeled multi-sub
        case SmartDownloadAudio.sub:
          // Generic sub — prefer those that are NOT dub
          if (!_matchesDub(title)) { s += 15; }
          if (title.contains('sub')) { s += 5; }
      }

      // Codec bonus (x265 preferred for smaller size)
      if (title.contains('x265') || title.contains('hevc')) s += 3;

      return s;
    }

    // Sort by score descending
    final ranked = [...torrents]..sort((a, b) => score(b).compareTo(score(a)));

    for (final t in ranked) {
      final link = t['link']?.toString() ?? t['magnet']?.toString() ?? '';
      if (link.isNotEmpty) return t;
    }
    return null;
  }

  bool _matchesDub(String title) {
    return title.contains('dub') ||
        title.contains('dubbed') ||
        (title.contains('dual') && title.contains('audio')) ||
        (title.contains('multi') && title.contains('audio'));
  }

  bool _matchesMultiSub(String title) {
    // Explicit 'multi sub' / 'multisub'
    if (title.contains('multi') && title.contains('sub')) return true;
    // Well-known multi-sub groups that don't tag explicitly
    const multiSubGroups = ['erai-raws', 'toonshub', 'subsplease'];
    for (final g in multiSubGroups) {
      if (title.contains(g)) return true;
    }
    return false;
  }

  // -------------------------------------------------------------------------
  // Enqueue in TorrentEngineService
  // -------------------------------------------------------------------------
  Future<SmartDownloadResult> _enqueueTorrent(Map<String, dynamic> torrent, MediaItem metadata) async {
    final magnet = torrent['link']?.toString() ??
        torrent['magnet']?.toString() ??
        '';
    final torrentName = torrent['title']?.toString() ?? 'Torrent';

    if (magnet.isEmpty) {
      return const SmartDownloadResult(
        success: false,
        errorMessage: 'El torrent no tiene enlace magnet válido.',
      );
    }

    try {
      final result = await TorrentEngineService.instance.addTorrent(magnet);
      if (result != null) {
        await TorrentMetadataService.instance.saveMetadata(result.infoHash, metadata);
        return SmartDownloadResult(success: true, torrentName: torrentName);
      } else {
        return SmartDownloadResult(
          success: false,
          torrentName: torrentName,
          errorMessage: 'No se pudo añadir el torrent al motor.',
        );
      }
    } catch (e) {
      return SmartDownloadResult(
        success: false,
        torrentName: torrentName,
        errorMessage: 'Error: $e',
      );
    }
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------
  int? _extractAnilistId(MediaItem metadata) {
    if (metadata.grandparentId != null) {
      return int.tryParse(metadata.grandparentId!);
    }
    if (metadata.id.startsWith('anime_ep_') || metadata.id.startsWith('anime_')) {
      final parts = metadata.id.split('_');
      if (parts.length > 2) return int.tryParse(parts[2]);
    }
    return null;
  }

  Future<List<ExtensionPlugin>> _getTorrentExtensions(MediaItem metadata) async {
    try {
      final list = await PluginExtensionsService.listExtensions();
      final disabledList = SettingsService.instance.read<List<dynamic>?>(SettingsService.disabledExtensions) ?? [];
      final enabledList = list.where((ext) => !disabledList.contains(ext.id)).toList();

      final targetType = metadata.isAnilist ? 'anime' : 'general';
      return enabledList.where((ext) {
        final isTorrent =
            ext.id.contains('torrent') || ext.id.contains('tosho') || ext.id.contains('bt');
        return isTorrent && ext.contentType == targetType;
      }).toList();
    } catch (_) {
      return [];
    }
  }
}
