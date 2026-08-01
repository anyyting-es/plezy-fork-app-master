import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import '../../focus/focusable_action_bar.dart';
import '../../media/media_item.dart';
import '../../providers/download_provider.dart';
import '../../services/settings_service.dart';
import '../../widgets/settings_builder.dart';
import '../../mixins/tab_navigation_mixin.dart';
import '../../mixins/refreshable.dart';
import '../../utils/grid_size_calculator.dart';
import '../../utils/platform_detector.dart';
import '../../widgets/desktop_app_bar.dart';
import '../../widgets/focusable_media_card.dart';
import '../../widgets/media_grid_delegate.dart';
import '../main_screen.dart';
import '../libraries/state_messages.dart';
import '../../i18n/strings.g.dart';
import '../../widgets/torrent_realtime_viewer.dart';
import 'sync_rules_screen.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => DownloadsScreenState();
}

class DownloadsScreenState extends State<DownloadsScreen>
    with TickerProviderStateMixin, TabNavigationMixin, FocusableTab {
  // Focus nodes for tab chips
  final _tvShowsTabChipFocusNode = FocusNode(debugLabel: 'tab_chip_tv_shows');
  final _moviesTabChipFocusNode = FocusNode(debugLabel: 'tab_chip_movies');
  final _queueTabChipFocusNode = FocusNode(debugLabel: 'tab_chip_queue');
  final _actionBarKey = GlobalKey<FocusableActionBarState>();

  @override
  List<FocusNode> get tabChipFocusNodes => [_tvShowsTabChipFocusNode, _moviesTabChipFocusNode, _queueTabChipFocusNode];

  @override
  void initState() {
    super.initState();
    suppressAutoFocus = true; // Start suppressed
    initTabNavigation();
  }

  @override
  void dispose() {
    _tvShowsTabChipFocusNode.dispose();
    _moviesTabChipFocusNode.dispose();
    _queueTabChipFocusNode.dispose();
    disposeTabNavigation();
    super.dispose();
  }

  @override
  void onTabChanged() {
    if (!tabController.indexIsChanging) {
      super.onTabChanged();
    }
  }

  @override
  void focusActiveTabIfReady() {
    suppressAutoFocus = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      getTabChipFocusNode(tabController.index).requestFocus();
    });
  }

  /// Focus the first item in the currently active tab
  void _focusCurrentTab() {
    // Re-enable auto-focus since user is navigating into tab content
    setState(() {
      suppressAutoFocus = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Focus will be handled by the tab content
    });
  }

  Widget _buildTabChip(String label, int index) {
    return buildTabChip(
      label,
      index,
      onSelectWhenActive: _focusCurrentTab,
      onNavigateDown: _focusCurrentTab,
      onNavigateToActions: () => _actionBarKey.currentState?.requestFocusOnFirst(),
    );
  }

  /// Build the app bar title - either tabs on desktop or simple title on mobile
  Widget _buildAppBarTitle() {
    // On desktop/TV with side nav, show tabs in app bar
    if (PlatformDetector.shouldUseSideNavigation(context)) {
      return Row(
        children: [
          _buildTabChip(t.downloads.tvShows, 0),
          const SizedBox(width: 8),
          _buildTabChip(t.downloads.movies, 1),
          const SizedBox(width: 8),
          _buildTabChip(t.downloads.manage, 2),
        ],
      );
    }

    // On mobile, show simple title
    return Text(t.downloads.title);
  }

  Widget _buildManageTabContent() {
    return const SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Embedded Real-Time Torrent Viewer (BitTorrent Backend)
          TorrentRealtimeViewer(
            isEmbedded: true,
            shrinkWrap: true,
          ),
          SizedBox(height: 32),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        primary: false,
        slivers: [
          DesktopSliverAppBar(
            title: _buildAppBarTitle(),
            floating: true,
            pinned: true,
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            surfaceTintColor: Colors.transparent,
            shadowColor: Colors.transparent,
            scrolledUnderElevation: 0,
            actions: [
              FocusableActionBar(
                key: _actionBarKey,
                onNavigateLeft: () => getTabChipFocusNode(tabCount - 1).requestFocus(),
                onNavigateDown: _focusCurrentTab,
                actions: [
                  FocusableAction(
                    icon: Symbols.rule_settings,
                    tooltip: t.downloads.activeSyncRules,
                    onPressed: () =>
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const SyncRulesScreen())),
                  ),
                ],
              ),
            ],
          ),
          SliverFillRemaining(
            child: Column(
              children: [
                // Tab selector chips (only on mobile - desktop has them in app bar)
                if (!PlatformDetector.shouldUseSideNavigation(context))
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    alignment: .centerLeft,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildTabChip(t.downloads.tvShows, 0),
                          const SizedBox(width: 8),
                          _buildTabChip(t.downloads.movies, 1),
                          const SizedBox(width: 8),
                          _buildTabChip(t.downloads.manage, 2),
                        ],
                      ),
                    ),
                  ),
                // Tab content
                Expanded(
                  child: TabBarView(
                    controller: tabController,
                    children: [
                      _DownloadsGridContent(
                        type: DownloadType.tvShows,
                        suppressAutoFocus: suppressAutoFocus,
                        onBack: focusTabBar,
                      ),
                      _DownloadsGridContent(
                        type: DownloadType.movies,
                        suppressAutoFocus: suppressAutoFocus,
                        onBack: focusTabBar,
                      ),
                      _buildManageTabContent(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum DownloadType { manage, tvShows, movies }

/// Grid content for TV Shows and Movies tabs
class _DownloadsGridContent extends StatefulWidget {
  final DownloadType type;
  final bool suppressAutoFocus;
  final VoidCallback? onBack;

  const _DownloadsGridContent({required this.type, required this.suppressAutoFocus, this.onBack});

  @override
  State<_DownloadsGridContent> createState() => _DownloadsGridContentState();
}

class _DownloadsGridContentState extends State<_DownloadsGridContent> {
  final FocusNode _firstItemFocusNode = FocusNode(debugLabel: 'DownloadsGrid_firstItem');

  @override
  void dispose() {
    _firstItemFocusNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_DownloadsGridContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When suppressAutoFocus changes from true to false, focus the first item
    if (oldWidget.suppressAutoFocus && !widget.suppressAutoFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _firstItemFocusNode.canRequestFocus) {
          _firstItemFocusNode.requestFocus();
        }
      });
    }
  }

  /// Navigate focus to the sidebar
  void _navigateToSidebar() {
    MainScreenFocusScope.of(context, listen: false)?.focusSidebar();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DownloadProvider>(
      builder: (context, downloadProvider, _) {
        final List<MediaItem> items = widget.type == DownloadType.tvShows
            ? downloadProvider.downloadedShows
            : downloadProvider.downloadedMovies;

        if (items.isEmpty) {
          return _buildEmptyState();
        }

        // Extra top padding for focus decoration (scale + border extends beyond item bounds)
        const effectivePadding = EdgeInsets.only(left: 8, right: 8, top: 8);

        return SettingsBuilder(
          prefs: const [SettingsService.libraryDensity, SettingsService.tvFullCardLayout],
          builder: (context) {
            final settings = SettingsService.instance;
            final density = settings.read(SettingsService.libraryDensity);
            final fullCardLayout = PlatformDetector.isTV() && settings.read(SettingsService.tvFullCardLayout);
            final maxCrossAxisExtent = GridSizeCalculator.getMaxCrossAxisExtent(context, density);
            // Use LayoutBuilder to get actual available width (accounting for sidebar)
            return LayoutBuilder(
              builder: (context, constraints) {
                final availableWidth = constraints.maxWidth - effectivePadding.left - effectivePadding.right;
                final gridSpacing = MediaGridDelegate.spacingFor(context: context, fullBleedImage: fullCardLayout);
                final columnCount = GridSizeCalculator.getColumnCount(
                  availableWidth,
                  maxCrossAxisExtent,
                  crossAxisSpacing: gridSpacing,
                );

                return GridView.builder(
                  addAutomaticKeepAlives: false,
                  addSemanticIndexes: false,
                  padding: effectivePadding,
                  // Allow focus decoration to render outside scroll bounds
                  clipBehavior: Clip.none,
                  gridDelegate: MediaGridDelegate.createDelegate(
                    context: context,
                    density: density,
                    fullBleedImage: fullCardLayout,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final isFirstColumn = GridSizeCalculator.isFirstColumn(index, columnCount);
                    final isFirst = index == 0;
                    return FocusableMediaCard(
                      item: item,
                      focusNode: isFirst ? _firstItemFocusNode : null,
                      onBack: widget.onBack,
                      isOffline: true, // Downloaded content works without server
                      fullBleedImage: fullCardLayout,
                      onNavigateLeft: isFirstColumn ? _navigateToSidebar : null,
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return EmptyStateWidget(
      message: t.downloads.noDownloads,
      subtitle: t.downloads.noDownloadsDescription,
      icon: Symbols.download_rounded,
      iconSize: 80,
    );
  }
}
