import 'dart:async';

import 'package:flutter/material.dart';

import '../../../services/app_toast.dart';
import '../application/music_player_controller.dart';
import '../domain/music_track.dart';
import '../infrastructure/music_library_store.dart';
import '../infrastructure/music_platform_gateway.dart';
import 'music_downloads_page.dart';
import 'music_player_dialogs.dart';
import 'music_track_page.dart';
import 'widgets/music_library_widgets.dart';
import 'widgets/music_online_search_view.dart';
import 'widgets/music_track_tile.dart';

class MusicPlayerPage extends StatefulWidget {
  const MusicPlayerPage({super.key});

  @override
  State<MusicPlayerPage> createState() => _MusicPlayerPageState();
}

enum MusicLibraryTab { local, favorites }

class _MusicPlayerPageState extends State<MusicPlayerPage> {
  final MusicPlayerController _player = MusicPlayerController.instance;
  final MusicLibraryStore _library = MusicLibraryStore.instance;
  final MusicPlatformGateway _platform = MusicPlatformGateway.instance;

  List<MusicTrack> _localTracks = const <MusicTrack>[];
  List<MusicTrack> _favorites = const <MusicTrack>[];
  List<String> _groups = const <String>[];
  String? _selectedGroup;
  bool _loadingLibrary = true;
  bool _scanning = false;
  MusicLibraryTab _selectionTab = MusicLibraryTab.local;
  final Set<String> _selectedTrackKeys = <String>{};

  bool get _selectionMode => _selectedTrackKeys.isNotEmpty;

  @override
  void initState() {
    super.initState();
    unawaited(_player.initialize());
    unawaited(_reloadLibrary());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || ModalRoute.of(context)?.settings.arguments != true) {
        return;
      }
      final current = _player.currentTrack;
      if (current != null) {
        unawaited(_openTrack(current));
      }
    });
  }

  Future<void> _reloadLibrary() async {
    final results = await Future.wait<Object>([
      _library.list(sourceType: MusicSourceType.local),
      _library.list(favoritesOnly: true),
      _library.listGroups(),
    ]);
    if (!mounted) return;
    final localTracks = results[0] as List<MusicTrack>;
    setState(() {
      _localTracks = localTracks;
      _favorites = (results[1] as List<MusicTrack>)
          .where((track) => !track.isRemote)
          .toList(growable: false);
      _groups = results[2] as List<String>;
      _loadingLibrary = false;
      final validKeys = <String>{
        ...localTracks.map((track) => track.trackKey),
        ..._favorites.map((track) => track.trackKey),
      };
      _selectedTrackKeys.removeWhere((key) => !validKeys.contains(key));
    });
  }

  Future<void> _scanLocalMusic() async {
    setState(() => _scanning = true);
    try {
      var granted = await _platform.hasAudioPermission();
      if (!granted) {
        granted = await _platform.requestAudioPermission();
      }
      if (!granted) {
        _toast('未授予音乐文件读取权限');
        return;
      }
      final rows = await _platform.scanLocalMusic();
      final tracks = rows
          .map(MusicTrack.fromPlatformMap)
          .toList(growable: false);
      await _library.replaceLocalTracks(tracks);
      await _reloadLibrary();
      _toast('已找到 ${tracks.length} 首本机歌曲');
    } catch (error) {
      _toast('扫描失败：$error');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _openTrack(MusicTrack track, {List<MusicTrack>? queue}) async {
    final effectiveQueue =
        queue ?? (track.isRemote ? null : _filterGroup(_localTracks));
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MusicTrackPage(track: track, queue: effectiveQueue),
      ),
    );
    await _reloadLibrary();
  }

  Future<void> _toggleFavorite(MusicTrack track) async {
    if (track.isRemote) return;
    try {
      await _player.setFavorite(track, !track.isFavorite);
      await _reloadLibrary();
    } catch (error) {
      _toast('收藏操作失败：$error');
    }
  }

  Future<void> _showSettings() async {
    await _player.initialize();
    if (!mounted) return;
    final settings = await showMusicSettingsDialog(context, _player.settings);
    if (settings == null) return;
    await _player.updateSettings(settings);
    _toast('音乐设置已保存');
  }

  Future<void> _showDownloads() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const MusicDownloadsPage()));
    await _reloadLibrary();
  }

  void _toggleSelection(MusicLibraryTab tab, String trackKey, bool selected) {
    setState(() {
      if (selected) {
        if (!_selectionMode) _selectionTab = tab;
        _selectedTrackKeys.add(trackKey);
      } else {
        _selectedTrackKeys.remove(trackKey);
      }
    });
  }

  void _selectAll(List<MusicTrack> tracks) {
    setState(() {
      _selectedTrackKeys
        ..clear()
        ..addAll(tracks.map((track) => track.trackKey));
    });
  }

  void _exitSelection() {
    setState(() {
      _selectedTrackKeys.clear();
    });
  }

  Future<void> _groupSelectedTracks() async {
    final selected = _localTracks
        .where((track) => _selectedTrackKeys.contains(track.trackKey))
        .toList(growable: false);
    if (selected.isEmpty) return;
    final groups = await _library.listGroups();
    if (!mounted) return;
    final group = await showMusicGroupDialog(
      context,
      currentGroup: '',
      existingGroups: groups,
    );
    if (group == null) return;
    for (final track in selected) {
      await _player.setGroup(track, group);
    }
    _exitSelection();
    await _reloadLibrary();
    _toast('已将 ${selected.length} 首歌曲加入分组');
  }

  Future<void> _deleteSelectedTracks() async {
    final pool = _selectionTab == MusicLibraryTab.local
        ? _localTracks
        : _favorites;
    final selected = pool
        .where((track) => _selectedTrackKeys.contains(track.trackKey))
        .toList(growable: false);
    if (selected.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('删除 ${selected.length} 首歌曲？'),
        content: const Text('将同时删除本地文件和音乐记录，此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    var deletedCount = 0;
    for (final track in selected) {
      try {
        await _player.deleteLocalTrack(track);
        deletedCount++;
      } on Object {
        // 跳过删除失败的歌曲，继续处理其他歌曲。
      }
    }
    _exitSelection();
    await _reloadLibrary();
    _toast(
      deletedCount == selected.length
          ? '已删除 $deletedCount 首歌曲'
          : '已删除 $deletedCount 首，${selected.length - deletedCount} 首删除失败',
    );
  }

  Future<void> _confirmDeleteTrack(MusicTrack track) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除本地歌曲？'),
        content: Text('将同时删除“${track.title}”的本地文件和音乐记录，此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _player.deleteLocalTrack(track);
      await _reloadLibrary();
      _toast('已删除');
    } catch (error) {
      _toast('删除失败：$error');
    }
  }

  void _toast(String message) => unawaited(AppToast.show(message));

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('音乐'),
          actions: [
            PopupMenuButton<String>(
              tooltip: '音乐菜单',
              onSelected: (value) {
                if (value == 'downloads') unawaited(_showDownloads());
                if (value == 'settings') unawaited(_showSettings());
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'downloads',
                  child: ListTile(
                    leading: Icon(Icons.download_done_rounded),
                    title: Text('下载记录'),
                  ),
                ),
                PopupMenuItem(
                  value: 'settings',
                  child: ListTile(
                    leading: Icon(Icons.tune_rounded),
                    title: Text('音乐设置'),
                  ),
                ),
              ],
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: '本机'),
              Tab(text: '在线'),
              Tab(text: '收藏'),
            ],
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: AnimatedBuilder(
                animation: _player.activeTrackKeyChanges,
                builder: (context, _) => TabBarView(
                  physics: _selectionMode
                      ? const NeverScrollableScrollPhysics()
                      : null,
                  children: [
                    _buildLocalTab(),
                    MusicOnlineSearchView(
                      player: _player,
                      bottomPadding: _musicListPadding(context).bottom,
                      onOpenTrack: (track, queue) =>
                          _openTrack(track, queue: queue),
                      onError: _toast,
                    ),
                    _buildFavoritesTab(),
                  ],
                ),
              ),
            ),
            MusicMiniPlayer(player: _player, onTap: _openTrack),
          ],
        ),
      ),
    );
  }

  Widget _buildLocalTab() {
    if (_loadingLibrary) {
      return const Center(child: CircularProgressIndicator());
    }
    final localTracks = _filterGroup(_localTracks);
    if (_selectionMode && _selectionTab == MusicLibraryTab.local) {
      return _buildSelectionList(
        tracks: localTracks,
        emptyIcon: Icons.library_music_outlined,
        emptyLabel: '暂无本机歌曲',
        showGroupAction: true,
      );
    }
    return RefreshIndicator(
      onRefresh: _scanLocalMusic,
      child: ListView(
        padding: _musicListPadding(context),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${localTracks.length} 首歌曲',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              IconButton.filledTonal(
                tooltip: _scanning ? '扫描中' : '重新扫描',
                onPressed: _scanning
                    ? null
                    : () => unawaited(_scanLocalMusic()),
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                icon: _scanning
                    ? const SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildGroupFilters(),
          if (_groups.isNotEmpty) const SizedBox(height: 8),
          if (localTracks.isEmpty)
            const MusicEmptyState(
              icon: Icons.library_music_outlined,
              label: '暂无本机歌曲',
            )
          else
            ...localTracks.map((track) => _trackTile(track)),
        ],
      ),
    );
  }

  Widget _buildFavoritesTab() {
    final filtered = _filterGroup(_favorites);
    if (_selectionMode && _selectionTab == MusicLibraryTab.favorites) {
      return _buildSelectionList(
        tracks: filtered,
        emptyIcon: Icons.favorite_border_rounded,
        emptyLabel: '暂无收藏歌曲',
        showGroupAction: false,
      );
    }
    return ListView(
      padding: _musicListPadding(context),
      children: [
        _buildGroupFilters(),
        if (_groups.isNotEmpty) const SizedBox(height: 8),
        if (filtered.isEmpty)
          const MusicEmptyState(
            icon: Icons.favorite_border_rounded,
            label: '暂无收藏歌曲',
          )
        else
          ...filtered.map((track) => _trackTile(track, queue: filtered)),
      ],
    );
  }

  Widget _buildGroupFilters() {
    if (_groups.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          FilterChip(
            label: const Text('全部'),
            selected: _selectedGroup == null,
            onSelected: (_) => setState(() => _selectedGroup = null),
          ),
          const SizedBox(width: 8),
          ..._groups.map(
            (group) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(group),
                selected: _selectedGroup == group,
                onSelected: (_) => setState(() => _selectedGroup = group),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionList({
    required List<MusicTrack> tracks,
    required IconData emptyIcon,
    required String emptyLabel,
    required bool showGroupAction,
  }) {
    return ListView(
      padding: _musicListPadding(context),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '已选 ${_selectedTrackKeys.length} 首',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            TextButton(
              onPressed: tracks.isEmpty ? null : () => _selectAll(tracks),
              child: const Text('全选'),
            ),
            if (showGroupAction)
              TextButton(
                onPressed: _selectedTrackKeys.isEmpty
                    ? null
                    : () => unawaited(_groupSelectedTracks()),
                child: const Text('加入分组'),
              ),
            TextButton(
              onPressed: _selectedTrackKeys.isEmpty
                  ? null
                  : () => unawaited(_deleteSelectedTracks()),
              child: Text(
                '删除',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
            TextButton(onPressed: _exitSelection, child: const Text('取消')),
          ],
        ),
        const SizedBox(height: 4),
        if (tracks.isEmpty)
          MusicEmptyState(icon: emptyIcon, label: emptyLabel)
        else
          ...tracks.map(
            (track) => MusicTrackTile(
              key: ValueKey(track.trackKey),
              track: track,
              isCurrent: _player.currentTrack?.trackKey == track.trackKey,
              selected: _selectedTrackKeys.contains(track.trackKey),
              onSelectChanged: (value) =>
                  _toggleSelection(_selectionTab, track.trackKey, value),
              onTap: () => _toggleSelection(
                _selectionTab,
                track.trackKey,
                !_selectedTrackKeys.contains(track.trackKey),
              ),
            ),
          ),
      ],
    );
  }

  List<MusicTrack> _filterGroup(List<MusicTrack> tracks) {
    final group = _selectedGroup;
    if (group == null) return tracks;
    return tracks.where((track) => track.groupName == group).toList();
  }

  Widget _trackTile(
    MusicTrack track, {
    List<MusicTrack>? queue,
  }) => MusicTrackTile(
    key: ValueKey(track.trackKey),
    track: track,
    isCurrent: _player.currentTrack?.trackKey == track.trackKey,
    onTap: () => unawaited(_openTrack(track, queue: queue)),
    onFavorite: track.isRemote ? null : () => unawaited(_toggleFavorite(track)),
    onSelectChanged: !track.isRemote
        ? (value) => _toggleSelection(
            queue == null ? MusicLibraryTab.local : MusicLibraryTab.favorites,
            track.trackKey,
            value,
          )
        : null,
    onDelete: track.sourceType == MusicSourceType.online
        ? null
        : () => unawaited(_confirmDeleteTrack(track)),
  );

  EdgeInsets _musicListPadding(BuildContext context) {
    return EdgeInsets.fromLTRB(
      12,
      12,
      12,
      12 + MediaQuery.viewPaddingOf(context).bottom,
    );
  }
}
