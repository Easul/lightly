import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/music_player_controller.dart';
import '../../domain/music_track.dart';
import 'music_library_widgets.dart';
import 'music_track_tile.dart';

class MusicOnlineSearchView extends StatefulWidget {
  const MusicOnlineSearchView({
    super.key,
    required this.player,
    required this.bottomPadding,
    required this.onTapTrack,
    required this.onError,
  });

  final MusicPlayerController player;
  final double bottomPadding;
  final Future<void> Function(MusicTrack track, List<MusicTrack> queue)
  onTapTrack;
  final ValueChanged<String> onError;

  @override
  State<MusicOnlineSearchView> createState() => _MusicOnlineSearchViewState();
}

class _MusicOnlineSearchViewState extends State<MusicOnlineSearchView> {
  late final TextEditingController _searchController = TextEditingController(
    text: widget.player.searchKeyword,
  );
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_loadNextPageIfNeeded);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_loadNextPageIfNeeded)
      ..dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _loadNextPageIfNeeded() {
    if (!_scrollController.hasClients ||
        _scrollController.position.extentAfter > 280 ||
        widget.player.isSearching ||
        !widget.player.searchHasMore) {
      return;
    }
    unawaited(_loadMore());
  }

  Future<void> _loadMore() async {
    try {
      await widget.player.loadMoreSearchResults();
    } catch (error) {
      widget.onError('$error');
    }
  }

  Future<void> _submitSearch() async {
    final keyword = _searchController.text.trim();
    if (keyword.isEmpty) return;
    FocusScope.of(context).unfocus();
    try {
      await widget.player.search(keyword);
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    } catch (error) {
      widget.onError('$error');
    }
  }

  void _clearSearch() {
    _searchController.clear();
    widget.player.clearSearch();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: AnimatedBuilder(
            animation: widget.player.searchChanges,
            builder: (context, _) => TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => unawaited(_submitSearch()),
              decoration: InputDecoration(
                hintText: '歌曲、歌手或专辑',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIconConstraints: const BoxConstraints(minWidth: 80),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_searchController.text.isNotEmpty ||
                        widget.player.searchResults.isNotEmpty)
                      IconButton(
                        tooltip: '清空搜索',
                        visualDensity: VisualDensity.compact,
                        onPressed: _clearSearch,
                        icon: const Icon(Icons.close_rounded, size: 20),
                      ),
                    IconButton(
                      tooltip: '搜索',
                      onPressed: widget.player.isSearching
                          ? null
                          : () => unawaited(_submitSearch()),
                      icon:
                          widget.player.isSearching &&
                              widget.player.searchResults.isEmpty
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.arrow_forward_rounded),
                    ),
                  ],
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ),
        Expanded(
          child: AnimatedBuilder(
            animation: Listenable.merge(<Listenable>[
              widget.player.searchChanges,
              widget.player.activeTrackKeyChanges,
            ]),
            builder: (context, _) {
              final tracks = widget.player.searchResults;
              if (tracks.isEmpty && !widget.player.isSearching) {
                return ListView(
                  padding: EdgeInsets.only(bottom: widget.bottomPadding),
                  children: [
                    if (widget.player.searchError != null)
                      _SearchError(message: widget.player.searchError!),
                    const MusicEmptyState(
                      icon: Icons.travel_explore_rounded,
                      label: '搜索在线歌曲',
                    ),
                  ],
                );
              }
              return ListView.builder(
                controller: _scrollController,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(12, 2, 12, widget.bottomPadding),
                itemCount: tracks.length + 1,
                itemBuilder: (context, index) {
                  if (index == tracks.length) {
                    if (widget.player.searchError != null) {
                      return _SearchError(message: widget.player.searchError!);
                    }
                    return widget.player.isSearching
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 18),
                            child: Center(
                              child: SizedBox.square(
                                dimension: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          )
                        : const SizedBox(height: 8);
                  }
                  final track = tracks[index];
                  return MusicTrackTile(
                    key: ValueKey(track.trackKey),
                    track: track,
                    isCurrent:
                        widget.player.currentTrack?.trackKey == track.trackKey,
                    onTap: () => unawaited(widget.onTapTrack(track, tracks)),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SearchError extends StatelessWidget {
  const _SearchError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }
}
