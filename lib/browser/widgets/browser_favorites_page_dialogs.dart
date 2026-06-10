part of 'browser_favorites_page.dart';

extension _BrowserFavoritesPageDialogs on BrowserFavoritesPageState {
  Future<void> _showAddEditDialog({BrowserFavorite? favorite}) async {
    final isEditing = favorite != null;
    _titleController.text = favorite?.title ?? '';
    _urlController.text = favorite?.url ?? '';

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isEditing ? '编辑收藏' : '添加收藏'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: '标题',
                hintText: '输入网站标题',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: '网址',
                hintText: 'https://example.com',
              ),
              keyboardType: TextInputType.url,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(isEditing ? '保存' : '添加'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      final title = _titleController.text.trim();
      var url = _urlController.text.trim();

      if (title.isEmpty || url.isEmpty) {
        return;
      }

      if (!url.contains('://')) {
        url = 'https://$url';
      }

      try {
        if (isEditing) {
          await _favoriteService.update(
            favorite.copyWith(title: title, url: url),
          );
        } else {
          await _favoriteService.insert(title: title, url: url);
        }
        await _loadFavorites();
      } catch (e) {
        if (mounted) {
          unawaited(AppToast.show('操作失败: $e'));
        }
      }
    }

    _titleController.clear();
    _urlController.clear();
  }

  Future<void> _showDeleteConfirm(BrowserFavorite favorite) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除收藏'),
        content: Text('确定要删除 "${favorite.title}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true && favorite.id != null && mounted) {
      await _favoriteService.delete(favorite.id!);
      await _loadFavorites();
    }
  }

  void _showOptionsBottomSheet(BrowserFavorite favorite) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.open_in_browser),
              title: const Text('打开'),
              onTap: () {
                Navigator.of(context).pop();
                widget.onOpenUrl(favorite.url);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('编辑'),
              onTap: () {
                Navigator.of(context).pop();
                _showAddEditDialog(favorite: favorite);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.delete,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                '删除',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () {
                Navigator.of(context).pop();
                _showDeleteConfirm(favorite);
              },
            ),
          ],
        ),
      ),
    );
  }
}
