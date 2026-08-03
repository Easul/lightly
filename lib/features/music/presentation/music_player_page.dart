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

class _MusicPlayerPageState extends State<MusicPlayerPage> {
  final MusicPlayerController _player = MusicPlayerController.instance;
  final MusicLibraryStore _library = MusicLibraryStore.instance;
  final MusicPlatformGateway _platform = MusicPlatformGateway.instance;

  List<MusicTrack> _localTracks = const <MusicTrack>[];
  List<MusicTrack> _downloadedTracks = const <MusicTrack>[];
  List<MusicTrack> _favorites = const <MusicTrack>[];
  List<String> _groups = const <String>[];
  String? _selectedGroup;
  bool _loadingLibrary = true;
  bool _scanning = false;

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
      _library.list(sourceType: MusicSourceType.downloaded),
      _library.list(favoritesOnly: true),
      _library.listGroups(),
    ]);
    if (!mounted) return;
    setState(() {
      _localTracks = results[0] as List<MusicTrack>;
      _downloadedTracks = results[1] as List<MusicTrack>;
      _favorites = results[2] as List<MusicTrack>;
      _groups = results[3] as List<String>;
      _loadingLibrary = false;
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
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MusicTrackPage(track: track, queue: queue),
      ),
    );
    await _reloadLibrary();
  }

  Future<void> _toggleFavorite(MusicTrack track) async {
    try {
      final updated = await _player.setFavorite(track, !track.isFavorite);
      setState(() {
        _localTracks = _replace(_localTracks, updated);
        _downloadedTracks = _replace(_downloadedTracks, updated);
      });
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
                  children: [
                    _buildLocalTab(),
                    MusicOnlineSearchView(
                      player: _player,
                      bottomPadding: _musicListPadding(context).bottom,
                      onOpenTrack: (track, queue) =>
                          _openTrack(track, queue: queue),
                      onToggleFavorite: _toggleFavorite,
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
    final downloadedTracks = _filterGroup(_downloadedTracks);
    final localTracks = _filterGroup(_localTracks);
    final deviceQueue = <MusicTrack>[...downloadedTracks, ...localTracks];
    return RefreshIndicator(
      onRefresh: _scanLocalMusic,
      child: ListView(
        padding: _musicListPadding(context),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${localTracks.length + downloadedTracks.length} 首歌曲',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              FilledButton.icon(
                onPressed: _scanning
                    ? null
                    : () => unawaited(_scanLocalMusic()),
                icon: _scanning
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
                label: Text(_scanning ? '扫描中' : '重新扫描'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildGroupFilters(),
          if (_groups.isNotEmpty) const SizedBox(height: 8),
          if (localTracks.isEmpty && downloadedTracks.isEmpty)
            const MusicEmptyState(
              icon: Icons.library_music_outlined,
              label: '暂无本机歌曲',
            )
          else ...[
            if (downloadedTracks.isNotEmpty) ...[
              const MusicSectionTitle(label: '已下载'),
              ...downloadedTracks.map(
                (track) => _trackTile(track, queue: deviceQueue),
              ),
            ],
            if (localTracks.isNotEmpty) ...[
              const MusicSectionTitle(label: '设备音乐'),
              ...localTracks.map(
                (track) => _trackTile(track, queue: deviceQueue),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildFavoritesTab() {
    final filtered = _filterGroup(_favorites);
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

  List<MusicTrack> _filterGroup(List<MusicTrack> tracks) {
    final group = _selectedGroup;
    if (group == null) return tracks;
    return tracks.where((track) => track.groupName == group).toList();
  }

  Widget _trackTile(MusicTrack track, {List<MusicTrack>? queue}) =>
      MusicTrackTile(
        key: ValueKey(track.trackKey),
        track: track,
        isCurrent: _player.currentTrack?.trackKey == track.trackKey,
        onTap: () => unawaited(_openTrack(track, queue: queue)),
        onFavorite: () => unawaited(_toggleFavorite(track)),
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

List<MusicTrack> _replace(List<MusicTrack> source, MusicTrack replacement) {
  return source
      .map(
        (track) => track.trackKey == replacement.trackKey ? replacement : track,
      )
      .toList(growable: false);
}
