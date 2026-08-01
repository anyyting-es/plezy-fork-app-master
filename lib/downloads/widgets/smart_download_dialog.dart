/// Smart Download Dialog
///
/// A premium modal that lets the user configure quality, audio/subtitle
/// preference and release group before kicking off an automated torrent
/// search-and-download for a media item (show, season, movie or episode).
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import '../../media/media_item.dart';
import '../../media/media_item_types.dart';
import '../../media/media_kind.dart';
import '../../services/settings_service.dart';
import '../../providers/download_provider.dart';
import '../../anime/models/anime_episode.dart';
import '../../anime/services/anizip_service.dart';
import '../../utils/app_logger.dart';
import '../smart_download_config.dart';
import '../smart_download_service.dart';

class SmartDownloadDialog extends StatefulWidget {
  final MediaItem metadata;

  const SmartDownloadDialog({super.key, required this.metadata});

  /// Convenience helper — shows the dialog and returns whether anything was
  /// successfully enqueued.
  static Future<bool> show(BuildContext context, MediaItem metadata) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      useRootNavigator: false,
      builder: (_) => SmartDownloadDialog(metadata: metadata),
    );
    return result ?? false;
  }

  @override
  State<SmartDownloadDialog> createState() => _SmartDownloadDialogState();
}

class _SmartDownloadDialogState extends State<SmartDownloadDialog>
    with SingleTickerProviderStateMixin {
  // --- user selections ---
  late SmartDownloadQuality _quality;
  late SmartDownloadAudio _audio;
  late SmartDownloadProvider _provider;

  // --- operation state ---
  bool _isDownloading = false;
  String _statusMessage = '';
  bool _done = false;
  bool _hadError = false;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  // --- manual selection flow state ---
  bool _isSearching = false;
  List<Map<String, dynamic>> _searchedTorrents = [];
  String? _searchError;
  bool _filtersExpanded = false;
  List<AnimeEpisode> _animeEpisodes = [];
  bool _userSelectedFilters = false;

  @override
  void initState() {
    super.initState();

    // Default quality to 1080p
    _quality = SmartDownloadQuality.q1080p;

    // Default audio based on app language
    final locale = SettingsService.instance.read(SettingsService.appLocale);
    _audio = _defaultAudioForLocale(locale.languageCode);

    // Default provider to any
    _provider = SmartDownloadProvider.any;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Load anime episodes and start search
    _initFlow();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _initFlow() async {
    await _loadAnimeEpisodesIfNeeded();
    await _performSearch();
  }

  SmartDownloadAudio _defaultAudioForLocale(String code) {
    if (code == 'ja') return SmartDownloadAudio.sub;
    if (code == 'en') return SmartDownloadAudio.multiSub;
    if (['es', 'pt', 'fr', 'de', 'it'].contains(code)) return SmartDownloadAudio.multiSub;
    return SmartDownloadAudio.multiSub;
  }

  Future<void> _loadAnimeEpisodesIfNeeded() async {
    if (!widget.metadata.isAnilist) return;

    try {
      final animeId = SmartTorrentDownloadService.instance.extractAnilistId(widget.metadata);
      if (animeId != null) {
        final eps = await AniZipService.getEpisodes(animeId);
        if (mounted) {
          setState(() {
            _animeEpisodes = eps;
          });
        }
      }
    } catch (e) {
      appLogger.e('Failed to load anime episodes for download dialog', error: e);
    }
  }

  int get firstMissingEpisode {
    if (widget.metadata.kind == MediaKind.episode) {
      return widget.metadata.index ?? 1;
    }
    if (_animeEpisodes.isEmpty) return 1;

    final downloadProvider = Provider.of<DownloadProvider>(context, listen: false);
    final animeId = SmartTorrentDownloadService.instance.extractAnilistId(widget.metadata);
    if (animeId == null) return 1;

    for (final ep in _animeEpisodes) {
      final epId = 'anime_ep_${animeId}_${ep.absoluteEpisodeNumber}';
      if (!downloadProvider.isDownloaded(epId) &&
          !downloadProvider.isDownloading(epId) &&
          !downloadProvider.isQueued(epId)) {
        return ep.episodeNumber;
      }
    }
    return 1;
  }

  String _sanitizeTitle(String t) {
    return t
        .replaceAll(RegExp(r'[-_.]+'), ' ')
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<void> _performSearch() async {
    if (!mounted) return;
    setState(() {
      _isSearching = true;
      _searchError = null;
      _searchedTorrents = [];
    });

    try {
      final isMovie = widget.metadata.kind == MediaKind.movie;
      final showTitle = widget.metadata.grandparentTitle ?? widget.metadata.title ?? '';

      String query = '';
      bool isBatch = false;
      if (isMovie) {
        query = _sanitizeTitle(showTitle);
      } else if (widget.metadata.isShow || widget.metadata.isSeason) {
        if (widget.metadata.isAnilist) {
          final epNum = firstMissingEpisode;
          query = '${_sanitizeTitle(showTitle)} ${epNum.toString().padLeft(2, '0')}';
        } else {
          query = _sanitizeTitle(showTitle);
          isBatch = true;
        }
      } else {
        final epNum = widget.metadata.index ?? 1;
        query = '${_sanitizeTitle(showTitle)} ${epNum.toString().padLeft(2, '0')}';
      }

      final rawTorrents = await SmartTorrentDownloadService.instance.searchTorrents(
        metadata: widget.metadata,
        query: query,
        isMovie: isMovie,
        isBatch: isBatch,
      );

      // Rank and sort based on quality and audio preferences
      final ranked = [...rawTorrents];

      // Filter by selected provider if specified
      if (_provider != SmartDownloadProvider.any) {
        final providerTag = _provider.tag.toLowerCase();
        ranked.retainWhere((t) {
          final title = (t['title'] as String? ?? '').toLowerCase();
          return title.contains(providerTag);
        });
      }

      int score(Map<String, dynamic> torrent) {
        final title = (torrent['title'] as String? ?? '').toLowerCase();
        int s = 0;

        final seeds = (torrent['seeders'] as num?)?.toInt() ?? 0;
        s += (seeds.clamp(0, 5000) / 100).round();

        if (_quality != SmartDownloadQuality.any) {
          if (title.contains(_quality.tag.toLowerCase())) { s += 30; }
        } else {
          if (title.contains('1080p')) { s += 20; }
          else if (title.contains('720p')) { s += 12; }
          else if (title.contains('480p')) { s += 5; }
        }

        switch (_audio) {
          case SmartDownloadAudio.dub:
            if (_matchesDub(title)) { s += 20; }
          case SmartDownloadAudio.multiAudio:
            if (title.contains('multi') && title.contains('audio')) { s += 20; }
            else if (title.contains('dual') && title.contains('audio')) { s += 15; }
          case SmartDownloadAudio.multiSub:
            if (_matchesMultiSub(title)) { s += 20; }
            else { s += 5; }
          case SmartDownloadAudio.sub:
            if (!_matchesDub(title)) { s += 15; }
            if (title.contains('sub')) { s += 5; }
        }

        if (title.contains('x265') || title.contains('hevc')) s += 3;

        return s;
      }

      if (!_userSelectedFilters) {
        // Strictly sort by seeders descending by default!
        ranked.sort((a, b) {
          final seedsA = (a['seeders'] as num?)?.toInt() ?? 0;
          final seedsB = (b['seeders'] as num?)?.toInt() ?? 0;
          return seedsB.compareTo(seedsA);
        });
      } else {
        // Sort by matched score
        ranked.sort((a, b) => score(b).compareTo(score(a)));
      }

      if (mounted) {
        setState(() {
          _searchedTorrents = ranked;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSearching = false;
          final errorStr = e.toString();
          _searchError = errorStr.contains('Extensiones')
              ? errorStr
              : 'Error al buscar torrents: $e';
        });
      }
    }
  }

  bool _matchesDub(String title) {
    return title.contains('dub') ||
        title.contains('dubbed') ||
        (title.contains('dual') && title.contains('audio')) ||
        (title.contains('multi') && title.contains('audio'));
  }

  bool _matchesMultiSub(String title) {
    if (title.contains('multi') && title.contains('sub')) return true;
    const multiSubGroups = ['erai-raws', 'toonshub', 'subsplease'];
    for (final g in multiSubGroups) {
      if (title.contains(g)) return true;
    }
    return false;
  }

  void _onFilterChanged() {
    _userSelectedFilters = true;
    _performSearch();
  }

  Future<void> _handleTorrentSelected(Map<String, dynamic> torrent) async {
    final isAnime = widget.metadata.isAnilist;
    final isShowOrSeason = widget.metadata.isShow || widget.metadata.isSeason;

    if (isAnime && isShowOrSeason) {
      final startEp = firstMissingEpisode;
      await _downloadAnimeSeries(torrent, startEp);
    } else {
      setState(() {
        _isDownloading = true;
        _done = false;
        _hadError = false;
        _statusMessage = 'Añadiendo torrent a la cola...';
      });

      final res = await SmartTorrentDownloadService.instance.enqueueTorrent(torrent, widget.metadata);
      if (!mounted) return;

      setState(() {
        _isDownloading = false;
        _done = true;
        _hadError = !res.success;
        _statusMessage = res.success
            ? '✓ Añadido: ${res.torrentName}'
            : res.errorMessage ?? 'Error al añadir torrent';
      });

      if (res.success) {
        await Future<void>.delayed(const Duration(milliseconds: 1800));
        if (mounted) Navigator.pop(context, true);
      }
    }
  }

  Future<void> _downloadAnimeSeries(Map<String, dynamic> selectedTorrent, int startEp) async {
    setState(() {
      _isDownloading = true;
      _done = false;
      _hadError = false;
      _statusMessage = 'Iniciando descarga de episodios...';
    });

    final animeId = SmartTorrentDownloadService.instance.extractAnilistId(widget.metadata);
    if (animeId == null) {
      setState(() {
        _isDownloading = false;
        _done = true;
        _hadError = true;
        _statusMessage = 'Error: ID de anime no válido.';
      });
      return;
    }

    final downloadProvider = Provider.of<DownloadProvider>(context, listen: false);

    // 1. Enqueue the selected torrent for the startEp
    setState(() {
      _statusMessage = 'Añadiendo Ep. $startEp...';
    });

    final startEpMatch = _animeEpisodes.firstWhere((ep) => ep.episodeNumber == startEp, orElse: () => _animeEpisodes.first);
    final startEpItem = MediaItem.anilist(
      id: 'anime_ep_${animeId}_${startEpMatch.absoluteEpisodeNumber}',
      kind: MediaKind.episode,
      title: startEpMatch.displayTitle,
      index: startEpMatch.episodeNumber,
      parentIndex: 1,
      parentId: 'anime_season_$animeId',
      grandparentId: widget.metadata.id,
      grandparentTitle: widget.metadata.title,
      summary: startEpMatch.overview,
      thumbPath: startEpMatch.image,
      originallyAvailableAt: startEpMatch.airDate,
      durationMs: startEpMatch.runtime != null ? startEpMatch.runtime! * 60000 : null,
    );

    final firstResult = await SmartTorrentDownloadService.instance.enqueueTorrent(selectedTorrent, startEpItem);
    if (!firstResult.success) {
      setState(() {
        _isDownloading = false;
        _done = true;
        _hadError = true;
        _statusMessage = 'No se pudo añadir el Ep. $startEp: ${firstResult.errorMessage}';
      });
      return;
    }

    // 2. Identify the subsequent missing episodes
    final missingEps = _animeEpisodes.where((ep) {
      if (ep.episodeNumber <= startEp) return false;
      final epId = 'anime_ep_${animeId}_${ep.absoluteEpisodeNumber}';
      return !downloadProvider.isDownloaded(epId) &&
             !downloadProvider.isDownloading(epId) &&
             !downloadProvider.isQueued(epId);
    }).toList();

    if (missingEps.isEmpty) {
      setState(() {
        _isDownloading = false;
        _done = true;
        _statusMessage = '✓ Añadido Ep. $startEp. Los demás episodios ya están al día.';
      });
      await Future<void>.delayed(const Duration(milliseconds: 1800));
      if (mounted) Navigator.pop(context, true);
      return;
    }

    final providerId = selectedTorrent['_provider'] as String? ?? '';
    final selectedTitle = selectedTorrent['title'] as String? ?? '';

    // 3. Search and enqueue remaining episodes from the same provider/extension
    int successCount = 1;
    for (final ep in missingEps) {
      setState(() {
        _statusMessage = 'Buscando Ep. ${ep.episodeNumber}... ($successCount/${missingEps.length + 1} añadidos)';
      });

      final expectedTitle = SmartTorrentDownloadService.instance.replaceEpisodeNumber(selectedTitle, startEp, ep.episodeNumber);
      if (expectedTitle == null) {
        appLogger.w('[SmartDownload] Could not generate expected title for Ep. ${ep.episodeNumber}');
        continue;
      }

      final query = SmartTorrentDownloadService.instance.cleanTitleForSearch(expectedTitle);

      try {
        final results = await SmartTorrentDownloadService.instance.searchTorrentsOnProvider(
          providerId: providerId,
          query: query,
          isMovie: false,
          metadata: widget.metadata,
        );

        Map<String, dynamic>? bestMatch;
        for (final candidate in results) {
          final candTitle = candidate['title'] as String? ?? '';
          if (SmartTorrentDownloadService.instance.titlesMatchExceptEpisode(selectedTitle, startEp, candTitle, ep.episodeNumber)) {
            bestMatch = candidate;
            break;
          }
        }

        if (bestMatch != null) {
          setState(() {
            _statusMessage = 'Añadiendo Ep. ${ep.episodeNumber}...';
          });

          final epItem = MediaItem.anilist(
            id: 'anime_ep_${animeId}_${ep.absoluteEpisodeNumber}',
            kind: MediaKind.episode,
            title: ep.displayTitle,
            index: ep.episodeNumber,
            parentIndex: 1,
            parentId: 'anime_season_$animeId',
            grandparentId: widget.metadata.id,
            grandparentTitle: widget.metadata.title,
            summary: ep.overview,
            thumbPath: ep.image,
            originallyAvailableAt: ep.airDate,
            durationMs: ep.runtime != null ? ep.runtime! * 60000 : null,
          );

          final res = await SmartTorrentDownloadService.instance.enqueueTorrent(bestMatch, epItem);
          if (res.success) {
            successCount++;
          }
        }
      } catch (e) {
        appLogger.e('[SmartDownload] Error downloading Ep. ${ep.episodeNumber}', error: e);
      }
    }

    setState(() {
      _isDownloading = false;
      _done = true;
      _statusMessage = '✓ Se añadieron $successCount episodios a la cola.';
    });

    await Future<void>.delayed(const Duration(milliseconds: 2000));
    if (mounted) Navigator.pop(context, true);
  }

  List<String> _parseTorrentTags(String title) {
    final tags = <String>[];
    
    final groupMatch = RegExp(r'^\[([^\]]+)\]').firstMatch(title);
    if (groupMatch != null) {
      tags.add(groupMatch.group(1)!.trim());
    }

    final resMatch = RegExp(r'\b(1080p|720p|480p|540p|2160p|4k)\b', caseSensitive: false).firstMatch(title);
    if (resMatch != null) {
      tags.add(resMatch.group(1)!.toLowerCase());
    }

    final audioMatch = RegExp(r'\b(dual[- ]audio|multi[- ]audio|dubbed|dub)\b', caseSensitive: false).firstMatch(title);
    if (audioMatch != null) {
      final raw = audioMatch.group(1)!.toLowerCase();
      if (raw.contains('dual')) {
        tags.add('DUAL');
      } else if (raw.contains('multi')) {
        tags.add('MULTI-AUDIO');
      } else {
        tags.add('DUB');
      }
    }

    final subMatch = RegExp(r'\b(multi[- ]subs?|eng[- ]subs?|subbed|sub)\b', caseSensitive: false).firstMatch(title);
    if (subMatch != null) {
      final raw = subMatch.group(1)!.toLowerCase();
      if (raw.contains('multi')) {
        tags.add('MULTI-SUB');
      } else {
        tags.add('SUB');
      }
    }

    final codecMatch = RegExp(r'\b(x265|x264|hevc|h\.265|h\.264)\b', caseSensitive: false).firstMatch(title);
    if (codecMatch != null) {
      tags.add(codecMatch.group(1)!.toUpperCase());
    }

    return tags;
  }

  String _formatSizeBytes(int bytes) {
    if (bytes == 0) return '0 B';
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
    double val = bytes.toDouble();
    int unit = 0;
    while (val >= 1024 && unit < sizes.length - 1) {
      val /= 1024;
      unit++;
    }
    return '${val.toStringAsFixed(1)} ${sizes[unit]}';
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Dialog(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 520,
          maxHeight: 680,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ---- header ----
            _buildHeader(cs, theme),

            // ---- content ----
            if (_isDownloading || _done)
              _buildProgressView(cs, theme)
            else ...[
              _buildFilterOptionsCard(cs, theme),
              const Divider(height: 1),
              if (_isSearching)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Column(
                      children: [
                        CircularProgressIndicator(color: cs.primary),
                        const SizedBox(height: 16),
                        Text(
                          'Buscando torrents disponibles...',
                          style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                )
              else if (_searchError != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
                  child: Center(
                    child: Column(
                      children: [
                        const Icon(Symbols.error_outline_rounded, size: 40, color: Colors.red),
                        const SizedBox(height: 12),
                        Text(
                          _searchError!,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurface),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _performSearch,
                          icon: const Icon(Symbols.refresh_rounded),
                          label: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                )
              else if (_searchedTorrents.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 50),
                  child: Center(
                    child: Column(
                      children: [
                        const Icon(Symbols.sentiment_dissatisfied_rounded, size: 40, color: Colors.grey),
                        const SizedBox(height: 12),
                        Text(
                          'No se encontraron torrents.',
                          style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Flexible(
                  child: _buildTorrentsList(cs, theme),
                ),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Header gradient strip
  // ---------------------------------------------------------------------------
  Widget _buildHeader(ColorScheme cs, ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.primaryContainer, cs.secondaryContainer],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Symbols.download_rounded, fill: 1, size: 26, color: cs.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Descargar',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: cs.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.metadata.displayTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onPrimaryContainer.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ),
          if (!_isDownloading && !_done)
            IconButton(
              onPressed: () => Navigator.pop(context, false),
              icon: Icon(Symbols.close_rounded, color: cs.onPrimaryContainer.withValues(alpha: 0.7)),
              iconSize: 20,
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Filter Options Card
  // ---------------------------------------------------------------------------
  Widget _buildFilterOptionsCard(ColorScheme cs, ThemeData theme) {
    return Card(
      margin: const EdgeInsets.all(12),
      elevation: 0,
      color: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          dense: true,
          title: Row(
            children: [
              Icon(Symbols.tune_rounded, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                'Ajustes de búsqueda',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
          initiallyExpanded: _filtersExpanded,
          onExpansionChanged: (val) {
            setState(() {
              _filtersExpanded = val;
            });
          },
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Calidad
            _sectionLabel(cs, theme, Symbols.hd_rounded, 'Calidad'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: SmartDownloadQuality.values.map((q) {
                return _ChoiceChip(
                  label: q.label,
                  selected: _quality == q,
                  onSelected: (_) {
                    setState(() => _quality = q);
                    _onFilterChanged();
                  },
                  colorScheme: cs,
                );
              }).toList(),
            ),
            const SizedBox(height: 12),

            // Audio
            _sectionLabel(cs, theme, Symbols.subtitles_rounded, 'Audio & Subtítulos'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: SmartDownloadAudio.values.map((a) {
                return _ChoiceChip(
                  label: a.label,
                  selected: _audio == a,
                  onSelected: (_) {
                    setState(() => _audio = a);
                    _onFilterChanged();
                  },
                  colorScheme: cs,
                );
              }).toList(),
            ),
            const SizedBox(height: 12),

            // Proveedor
            _sectionLabel(cs, theme, Symbols.group_rounded, 'Grupo / Proveedor'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: SmartDownloadProvider.values.map((p) {
                return _ChoiceChip(
                  label: p.label,
                  selected: _provider == p,
                  onSelected: (_) {
                    setState(() => _provider = p);
                    _onFilterChanged();
                  },
                  colorScheme: cs,
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(ColorScheme cs, ThemeData theme, IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 14, color: cs.primary),
        const SizedBox(width: 6),
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: cs.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Torrents list view
  // ---------------------------------------------------------------------------
  Widget _buildTorrentsList(ColorScheme cs, ThemeData theme) {
    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      itemCount: _searchedTorrents.length,
      itemBuilder: (context, index) {
        final torrent = _searchedTorrents[index];
        final title = torrent['title'] as String? ?? 'Sin título';
        final providerId = torrent['_provider'] as String? ?? '';
        final seeds = (torrent['seeders'] as num?)?.toInt() ?? 0;
        final leeches = (torrent['leechers'] as num?)?.toInt() ?? 0;
        final sizeBytes = (torrent['size'] as num?)?.toInt() ?? 0;

        final sizeStr = _formatSizeBytes(sizeBytes);
        final tags = _parseTorrentTags(title);

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          elevation: 0,
          color: cs.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _handleTorrentSelected(torrent),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: cs.primaryContainer,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                providerId.toUpperCase(),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: cs.onPrimaryContainer,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 9,
                                ),
                              ),
                            ),
                            ...tags.map((tag) {
                              Color badgeColor = cs.primary;
                              final lowerTag = tag.toLowerCase();

                              if (lowerTag.contains('1080p') || lowerTag.contains('4k') || lowerTag.contains('2160p')) {
                                badgeColor = Colors.teal;
                              } else if (lowerTag.contains('720p')) {
                                badgeColor = Colors.blue;
                              } else if (lowerTag.contains('dual') || lowerTag.contains('multi')) {
                                badgeColor = Colors.deepOrange;
                              } else if (lowerTag.contains('x265') || lowerTag.contains('hevc')) {
                                badgeColor = Colors.purple;
                              } else {
                                badgeColor = cs.secondary;
                              }

                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: badgeColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: badgeColor.withValues(alpha: 0.25), width: 1),
                                ),
                                child: Text(
                                  tag,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: badgeColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 9,
                                  ),
                                ),
                              );
                            }),
                            const SizedBox(width: 4),
                            Text(
                              sizeStr,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Symbols.arrow_upward_rounded, size: 14, color: Colors.green),
                      const SizedBox(width: 1),
                      Text(
                        '$seeds',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Symbols.arrow_downward_rounded, size: 14, color: Colors.red),
                      const SizedBox(width: 1),
                      Text(
                        '$leeches',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.red,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Progress / result view
  // ---------------------------------------------------------------------------
  Widget _buildProgressView(ColorScheme cs, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        children: [
          if (!_done)
            AnimatedBuilder(
              animation: _pulseAnim,
              builder: (ctx, child) => Opacity(
                opacity: _pulseAnim.value,
                child: Icon(
                  Symbols.downloading_rounded,
                  size: 52,
                  color: cs.primary,
                  fill: 1,
                ),
              ),
            )
          else
            Icon(
              _hadError ? Symbols.error_outline_rounded : Symbols.check_circle_rounded,
              size: 52,
              fill: 1,
              color: _hadError ? cs.error : Colors.green,
            ),
          const SizedBox(height: 16),
          Text(
            _done
                ? (_hadError ? 'Error' : '¡Añadido a la cola!')
                : 'Procesando descargas...',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _statusMessage,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          if (_done && _hadError) ...[
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cerrar'),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reusable styled chip
// ---------------------------------------------------------------------------
class _ChoiceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final ColorScheme colorScheme;

  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.onSelected,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      child: FilterChip(
        label: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? cs.onPrimary : cs.onSurface,
          ),
        ),
        selected: selected,
        onSelected: onSelected,
        checkmarkColor: cs.onPrimary,
        selectedColor: cs.primary,
        backgroundColor: cs.surfaceContainerHighest,
        side: BorderSide(
          color: selected ? cs.primary : cs.outlineVariant,
          width: selected ? 1.5 : 1,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        visualDensity: VisualDensity.compact,
        showCheckmark: false,
      ),
    );
  }
}
