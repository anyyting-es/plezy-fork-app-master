import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../services/torrent_engine_service.dart';
import '../services/torrent_metadata_service.dart';
import '../media/media_item_types.dart';
import '../i18n/strings.g.dart';
import 'optimized_media_image.dart';
import '../utils/platform_detector.dart';

/// Real-time torrent viewer dialog and bottom sheet for monitoring backend BitTorrent downloads.
class TorrentRealtimeViewer extends StatefulWidget {
  final bool isEmbedded;
  final bool shrinkWrap;
  final ScrollPhysics? physics;

  const TorrentRealtimeViewer({
    super.key,
    this.isEmbedded = false,
    this.shrinkWrap = false,
    this.physics,
  });

  /// Opens the real-time torrent monitor as a modal dialog or bottom sheet depending on screen size.
  static Future<void> show(BuildContext context) {
    if (PlatformDetector.isMobile(context)) {
      return showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const FractionallySizedBox(
          heightFactor: 0.88,
          child: TorrentRealtimeViewer(),
        ),
      );
    }
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => const Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.all(24),
        child: SizedBox(
          width: 850,
          height: 650,
          child: TorrentRealtimeViewer(),
        ),
      ),
    );
  }

  @override
  State<TorrentRealtimeViewer> createState() => _TorrentRealtimeViewerState();
}

class _TorrentRealtimeViewerState extends State<TorrentRealtimeViewer> {
  late final Stream<List<TorrentInfo>> _torrentsStream;
  final Map<String, bool> _expandedFiles = {};

  @override
  void initState() {
    super.initState();
    _torrentsStream = TorrentEngineService.instance.watchTorrents();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final content = StreamBuilder<List<TorrentInfo>>(
      stream: _torrentsStream,
      builder: (context, snapshot) {
        final torrents = snapshot.data ?? [];
        final isEngineRunning = TorrentEngineService.instance.isRunning;

        double totalDownloadSpeed = 0;
        double totalUploadSpeed = 0;
        for (final t in torrents) {
          totalDownloadSpeed += t.downloadSpeed;
          totalUploadSpeed += t.uploadSpeed;
        }

        Widget listWidget;
        if (!isEngineRunning) {
          listWidget = _buildEngineStoppedState(context);
        } else if (torrents.isEmpty) {
          listWidget = _buildEmptyState(context);
        } else {
          listWidget = ListView.builder(
            shrinkWrap: widget.shrinkWrap,
            physics: widget.physics ?? (widget.shrinkWrap ? const NeverScrollableScrollPhysics() : null),
            padding: const EdgeInsets.all(16),
            itemCount: torrents.length,
            itemBuilder: (context, index) {
              final torrent = torrents[index];
              final isExpanded = _expandedFiles[torrent.infoHash] ?? false;
              return _buildTorrentCard(
                context,
                torrent: torrent,
                isExpanded: isExpanded,
                onToggleExpand: () {
                  setState(() {
                    _expandedFiles[torrent.infoHash] = !isExpanded;
                  });
                },
              );
            },
          );
        }

        return Column(
          mainAxisSize: widget.shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
          children: [
            // ── Top Header ──────────────────────────────────────────
            _buildHeader(
              context,
              isEngineRunning: isEngineRunning,
              torrentCount: torrents.length,
              totalDownloadSpeed: totalDownloadSpeed,
              totalUploadSpeed: totalUploadSpeed,
            ),

            Divider(height: 1, thickness: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.3)),

            // ── Torrent List Body ───────────────────────────────────
            if (widget.shrinkWrap) listWidget else Expanded(child: listWidget),
          ],
        );
      },
    );

    if (widget.isEmbedded) {
      return Container(
        color: Colors.transparent,
        child: content,
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: content,
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context, {
    required bool isEngineRunning,
    required int torrentCount,
    required double totalDownloadSpeed,
    required double totalUploadSpeed,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: widget.isEmbedded ? Colors.transparent : colorScheme.surfaceContainerLow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Symbols.downloading,
                  color: colorScheme.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.downloads.manageTitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isEngineRunning ? Colors.greenAccent : colorScheme.error,
                            boxShadow: [
                              BoxShadow(
                                color: (isEngineRunning ? Colors.greenAccent : colorScheme.error)
                                    .withValues(alpha: 0.6),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isEngineRunning ? t.downloads.activeDownloads : t.downloads.noDownloads,
                          style: TextStyle(
                            fontSize: 12,
                            color: isEngineRunning ? Colors.greenAccent : colorScheme.error,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!widget.isEmbedded)
                IconButton(
                  icon: Icon(Icons.close, color: colorScheme.onSurfaceVariant),
                  tooltip: t.common.close,
                  onPressed: () => Navigator.of(context).pop(),
                ),
            ],
          ),

          if (isEngineRunning && torrentCount > 0) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                _buildStatHeaderChip(
                  context,
                  icon: Symbols.download,
                  iconColor: Colors.cyanAccent,
                  label: t.downloads.downloadSpeed,
                  value: formatSpeed(totalDownloadSpeed),
                ),
                const SizedBox(width: 10),
                _buildStatHeaderChip(
                  context,
                  icon: Symbols.upload,
                  iconColor: Colors.orangeAccent,
                  label: t.downloads.uploadSpeed,
                  value: formatSpeed(totalUploadSpeed),
                ),
                const SizedBox(width: 10),
                _buildStatHeaderChip(
                  context,
                  icon: Symbols.folder_zip,
                  iconColor: colorScheme.primary,
                  label: t.downloads.title,
                  value: '$torrentCount',
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatHeaderChip(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEngineStoppedState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Symbols.cloud_off, size: 64, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
            const SizedBox(height: 16),
            Text(
              'El motor de descargas no está iniciado',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
            ),
            const SizedBox(height: 8),
            Text(
              'Pulsa el botón para encender el servicio.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Symbols.power_settings_new),
              label: const Text('Iniciar Motor'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              onPressed: () async {
                await TorrentEngineService.instance.start();
                setState(() {});
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Symbols.wifi_tethering_off, size: 64, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
            const SizedBox(height: 16),
            Text(
              t.downloads.noDownloads,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
            ),
            const SizedBox(height: 8),
            Text(
              t.downloads.noDownloadsDescription,
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTorrentCard(
    BuildContext context, {
    required TorrentInfo torrent,
    required bool isExpanded,
    required VoidCallback onToggleExpand,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isCompleted = torrent.progress >= 100 || (torrent.size > 0 && torrent.downloaded >= torrent.size);

    // Look up metadata
    final metadata = TorrentMetadataService.instance.getMetadata(torrent.infoHash);
    
    final showTitle = metadata != null 
        ? (metadata.isEpisode ? (metadata.grandparentTitle ?? metadata.title ?? '') : (metadata.title ?? ''))
        : (torrent.name.isNotEmpty ? torrent.name : torrent.infoHash);
        
    final episodeTitle = metadata?.isEpisode == true ? metadata!.title : null;
    final seasonNumber = metadata?.parentIndex;
    final episodeNumber = metadata?.index;
    
    final hasEpisodeInfo = metadata?.isEpisode == true && seasonNumber != null && episodeNumber != null;
    final subtitleText = hasEpisodeInfo 
        ? 'Temporada $seasonNumber • Episodio $episodeNumber${episodeTitle != null && episodeTitle.isNotEmpty ? ' - $episodeTitle' : ''}'
        : (metadata?.isMovie == true ? '' : (metadata?.year?.toString() ?? ''));
    
    final imagePath = metadata != null
        ? (metadata.isEpisode ? (metadata.grandparentThumbPath ?? metadata.thumbPath) : metadata.thumbPath)
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCompleted
              ? Colors.greenAccent.withValues(alpha: 0.3)
              : torrent.downloadSpeed > 0
                  ? colorScheme.primary.withValues(alpha: 0.3)
                  : colorScheme.outlineVariant.withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Main Content Row (Poster + Details) ──────────────────────
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Poster Image
                  if (imagePath != null && imagePath.isNotEmpty) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 70,
                        height: 105,
                        child: OptimizedMediaImage.poster(
                          imagePath: imagePath,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                  ] else ...[
                    // Fallback visual icon
                    Container(
                      width: 70,
                      height: 105,
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        metadata?.isMovie == true ? Symbols.movie : Symbols.folder_zip,
                        size: 32,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 16),
                  ],

                  // Details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    showTitle,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      height: 1.2,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (subtitleText.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      subtitleText,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: colorScheme.onSurfaceVariant,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (!isCompleted) ...[
                              IconButton(
                                icon: Icon(
                                  torrent.paused
                                      ? Symbols.play_arrow_rounded
                                      : Symbols.pause_rounded,
                                  color: colorScheme.primary,
                                ),
                                tooltip: torrent.paused
                                    ? t.common.resume
                                    : t.common.pause,
                                onPressed: () async {
                                  if (torrent.paused) {
                                    await TorrentEngineService.instance.resumeTorrent(torrent.infoHash);
                                  } else {
                                    await TorrentEngineService.instance.pauseTorrent(torrent.infoHash);
                                  }
                                },
                              ),
                            ],
                            IconButton(
                              icon: Icon(Symbols.delete_outline, color: colorScheme.error),
                              tooltip: t.common.delete,
                              onPressed: () => _confirmRemoveTorrent(context, torrent),
                            ),
                          ],
                        ),
                        if (metadata?.summary != null && metadata!.summary!.isNotEmpty) ...[
                           const SizedBox(height: 6),
                          Text(
                            metadata.summary!,
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 12),

                        // Progress info
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              isCompleted
                                  ? t.downloads.completed
                                  : torrent.paused
                                      ? t.libraries.anilist.paused
                                      : torrent.downloadSpeed > 0
                                          ? '${t.downloads.downloading}... (${torrent.downloadSpeedFormatted})'
                                          : t.downloads.connecting,
                              style: TextStyle(
                                fontSize: 12,
                                color: isCompleted
                                    ? Colors.greenAccent
                                    : torrent.paused
                                        ? colorScheme.outline
                                        : torrent.downloadSpeed > 0
                                            ? Colors.cyanAccent
                                            : colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              torrent.progressFormatted,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: isCompleted ? Colors.greenAccent : colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: (torrent.progress / 100.0).clamp(0.0, 1.0),
                            minHeight: 6,
                            backgroundColor: colorScheme.surfaceContainerHighest,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isCompleted
                                  ? Colors.greenAccent
                                  : torrent.paused
                                      ? colorScheme.outline
                                      : torrent.downloadSpeed > 0
                                          ? Colors.cyanAccent
                                          : colorScheme.primary,
                            ),
                          ),
                        ),
                        if (!isCompleted && torrent.downloadSpeed > 0) ...[
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${torrent.downloadedFormatted} / ${torrent.sizeFormatted}',
                                style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                              ),
                              Text(
                                '${t.downloads.eta}: ${torrent.etaFormatted}',
                                style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Technical Details Accordion Toggle ──────────────────────
            InkWell(
              onTap: onToggleExpand,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
                  border: Border(
                    top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.15)),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isExpanded ? Symbols.expand_less : Symbols.expand_more,
                      size: 20,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      t.downloads.technicalDetails,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      isExpanded ? t.downloads.hideTechnical : t.downloads.showTechnical,
                      style: TextStyle(fontSize: 12, color: colorScheme.primary, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ),

            if (isExpanded) ...[
              Container(
                color: colorScheme.surfaceContainerLow.withValues(alpha: 0.5),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'HASH: ',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant),
                        ),
                        Expanded(
                          child: Text(
                            torrent.infoHash,
                            style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: colorScheme.onSurfaceVariant),
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.copy, size: 14, color: colorScheme.onSurfaceVariant),
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(4),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: torrent.infoHash));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Hash copiado al portapapeles'),
                                duration: Duration(seconds: 1),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    GridView.count(
                      crossAxisCount: MediaQuery.of(context).size.width < 600 ? 2 : 4,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      childAspectRatio: 2.5,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      children: [
                        _buildMetricCard(
                          context,
                          title: t.downloads.downloadSpeed,
                          value: torrent.downloadSpeedFormatted,
                          icon: Symbols.speed,
                          iconColor: Colors.cyanAccent,
                          subtitle: 'Up: ${torrent.uploadSpeedFormatted}',
                        ),
                        _buildMetricCard(
                          context,
                          title: t.downloads.seeds,
                          value: '${torrent.seeders}',
                          icon: Symbols.nature,
                          iconColor: Colors.greenAccent,
                          subtitle: 'Connected seeds',
                        ),
                        _buildMetricCard(
                          context,
                          title: t.downloads.peers,
                          value: '${torrent.leechers}',
                          icon: Symbols.group,
                          iconColor: Colors.amberAccent,
                          subtitle: 'Connected peers',
                        ),
                        _buildMetricCard(
                          context,
                          title: t.downloads.eta,
                          value: torrent.etaFormatted,
                          icon: Symbols.timer,
                          iconColor: Colors.purpleAccent,
                          subtitle: '${torrent.downloadedFormatted} / ${torrent.sizeFormatted}',
                        ),
                      ],
                    ),
                    if (torrent.files.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        '${t.downloads.torrentInfo} - Archivos (${torrent.files.length})',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: torrent.files.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 6),
                        itemBuilder: (context, fileIndex) {
                          final file = torrent.files[fileIndex];
                          return _buildFileItem(context, file);
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard(
    BuildContext context, {
    required String title,
    required String value,
    required IconData icon,
    required Color iconColor,
    required String subtitle,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 10,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 9,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileItem(BuildContext context, TorrentFile file) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDone = file.progress >= 100 || (file.size > 0 && file.downloaded >= file.size);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isDone ? Symbols.check_circle : Symbols.description,
                size: 16,
                color: isDone ? Colors.greenAccent : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  file.path,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: colorScheme.onSurface),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${file.downloadedFormatted} / ${file.sizeFormatted}',
                style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (file.progress / 100.0).clamp(0.0, 1.0),
              minHeight: 4,
              backgroundColor: colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(
                isDone ? Colors.greenAccent : colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRemoveTorrent(BuildContext context, TorrentInfo torrent) async {
    bool deleteFiles = true;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(t.downloads.deleteConfirmTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.downloads.deleteConfirmMessage),
              const SizedBox(height: 16),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t.downloads.deleteConfirmCheckbox),
                value: deleteFiles,
                onChanged: (val) {
                  setDialogState(() {
                    deleteFiles = val ?? false;
                  });
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: Text(t.common.cancel),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              child: Text(t.common.delete),
            ),
          ],
        ),
      ),
    );

    if (confirm == true) {
      await TorrentEngineService.instance.removeTorrent(
        torrent.infoHash,
        deleteFiles: deleteFiles,
      );
      await TorrentMetadataService.instance.deleteMetadata(torrent.infoHash);
      setState(() {});
    }
  }
}
