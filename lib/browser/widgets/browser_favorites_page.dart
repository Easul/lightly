import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/app_toast.dart';
import '../../theme/app_theme.dart';
import '../../widgets/shared/primary_button.dart';
import '../models/browser_favorite.dart';
import '../services/browser_favorite_service.dart';
import '../utils/browser_url_utils.dart';
import 'browser_favorite_icon.dart';

part 'browser_favorites_page_dialogs.dart';

typedef BrowserFavoritesInputResolver = String Function(String input);

String defaultBrowserFavoritesInputResolver(String input) {
  final resolvedUrl = normalizeBrowserUrl(input);
  if (resolvedUrl != null) {
    return resolvedUrl;
  }
  return 'https://www.google.com/search?q=${Uri.encodeComponent(input)}';
}

class BrowserFavoritesPage extends StatefulWidget {
  const BrowserFavoritesPage({
    super.key,
    required this.onOpenUrl,
    this.onAddFavorite,
    this.resolveSubmittedInput = defaultBrowserFavoritesInputResolver,
  });

  final ValueChanged<String> onOpenUrl;
  final VoidCallback? onAddFavorite;
  final BrowserFavoritesInputResolver resolveSubmittedInput;

  @override
  State<BrowserFavoritesPage> createState() => BrowserFavoritesPageState();
}

class BrowserFavoritesPageState extends State<BrowserFavoritesPage> {
  final BrowserFavoriteService _favoriteService = BrowserFavoriteService();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();

  List<BrowserFavorite> _favorites = [];
  List<BrowserFavorite> _filteredFavorites = [];
  bool _isLoading = true;
  int? _draggingFavoriteId;
  bool _reorderMode = false;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _titleController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _loadFavorites() async {
    try {
      final favorites = await _favoriteService.query();
      if (!mounted) {
        return;
      }
      setState(() {
        _favorites = favorites;
        _filteredFavorites = favorites;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _filterFavorites(String query) {
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) {
      setState(() {
        _filteredFavorites = _favorites;
      });
      return;
    }

    setState(() {
      _filteredFavorites = _favorites
          .where(
            (f) =>
                f.title.toLowerCase().contains(trimmed) ||
                f.url.toLowerCase().contains(trimmed),
          )
          .toList();
    });
  }

  Future<void> _reorderFavorite(
    BrowserFavorite dragged,
    BrowserFavorite target,
  ) async {
    final oldIndex = _favorites.indexWhere((item) => item.id == dragged.id);
    final newIndex = _favorites.indexWhere((item) => item.id == target.id);
    if (oldIndex == -1 || newIndex == -1 || oldIndex == newIndex) {
      return;
    }
    await _favoriteService.reorder(oldIndex, newIndex);
    await _loadFavorites();
  }

  Future<void> showAddFavoriteDialog() async {
    await _showAddEditDialog();
  }

  Future<void> refreshFavorites() async {
    await _loadFavorites();
  }

  void toggleReorderMode() {
    setState(() {
      _reorderMode = !_reorderMode;
      _draggingFavoriteId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Header with artistic text
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 42, bottom: 24),
                child: Center(
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Mint Start',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '若轻',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontSize: 34, letterSpacing: 6),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '简洁、轻盈、自然的收藏起点',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Search box
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.cardBackground,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    boxShadow: AppTheme.softShadow(0.04),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: _filterFavorites,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (value) {
                      final normalized = value.trim();
                      if (normalized.isNotEmpty) {
                        widget.onOpenUrl(
                          widget.resolveSubmittedInput(normalized),
                        );
                      }
                    },
                    decoration: InputDecoration(
                      hintText: '搜索或输入网址',
                      hintStyle: Theme.of(context).textTheme.bodyMedium,
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      suffixIcon: ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _searchController,
                        builder: (context, value, child) {
                          if (value.text.isEmpty) {
                            return const SizedBox.shrink();
                          }

                          return IconButton(
                            icon: Icon(
                              Icons.close_rounded,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                            onPressed: () {
                              _searchController.clear();
                              _filterFavorites('');
                            },
                          );
                        },
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Favorites grid
            if (_isLoading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(36),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (_filteredFavorites.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(48),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.bookmark_border,
                          size: 64,
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _searchController.text.isEmpty ? '暂无收藏' : '未找到匹配的收藏',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontSize: 16,
                          ),
                        ),
                        if (_searchController.text.isEmpty) ...[
                          const SizedBox(height: 24),
                          PrimaryButton(
                            onPressed: () => _showAddEditDialog(),
                            icon: Icons.add_rounded,
                            label: '添加收藏',
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              )
            else
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      const horizontalSpacing = 8.0;
                      const verticalSpacing = 10.0;
                      final columnCount = constraints.maxWidth >= 330 ? 5 : 4;
                      final tileWidth =
                          (constraints.maxWidth -
                              horizontalSpacing * (columnCount - 1)) /
                          columnCount;

                      return Wrap(
                        spacing: horizontalSpacing,
                        runSpacing: verticalSpacing,
                        children: _filteredFavorites.map((favorite) {
                          final tile = SizedBox(
                            width: tileWidth,
                            child: BrowserFavoriteIcon(
                              url: favorite.url,
                              title: favorite.title,
                              size: 40,
                              onTap: () => widget.onOpenUrl(favorite.url),
                              onLongPress: _reorderMode
                                  ? null
                                  : () => _showOptionsBottomSheet(favorite),
                            ),
                          );

                          if (_searchController.text.trim().isNotEmpty ||
                              !_reorderMode) {
                            return tile;
                          }

                          return DragTarget<BrowserFavorite>(
                            onWillAcceptWithDetails: (details) =>
                                details.data.id != favorite.id,
                            onAcceptWithDetails: (details) async {
                              await _reorderFavorite(details.data, favorite);
                              if (mounted) {
                                setState(() {
                                  _draggingFavoriteId = null;
                                });
                              }
                            },
                            builder: (context, candidateData, rejectedData) {
                              return LongPressDraggable<BrowserFavorite>(
                                data: favorite,
                                onDragStarted: () {
                                  setState(() {
                                    _draggingFavoriteId = favorite.id;
                                  });
                                },
                                onDragEnd: (_) {
                                  if (mounted) {
                                    setState(() {
                                      _draggingFavoriteId = null;
                                    });
                                  }
                                },
                                feedback: Material(
                                  color: Colors.transparent,
                                  child: Opacity(opacity: 0.92, child: tile),
                                ),
                                childWhenDragging: Opacity(
                                  opacity: 0.25,
                                  child: tile,
                                ),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    color: candidateData.isNotEmpty
                                        ? Theme.of(context)
                                              .colorScheme
                                              .primaryContainer
                                              .withValues(alpha: 0.5)
                                        : (_draggingFavoriteId == favorite.id
                                              ? Theme.of(context)
                                                    .colorScheme
                                                    .surfaceContainerHigh
                                              : Colors.transparent),
                                  ),
                                  child: tile,
                                ),
                              );
                            },
                          );
                        }).toList(),
                      );
                    },
                  ),
                ),
              ),

            // Bottom padding
            const SliverToBoxAdapter(child: SizedBox(height: 48)),
          ],
        ),
      ),
    );
  }
}
