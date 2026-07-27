import 'package:flutter/material.dart';

import '../models/browser_tab_session.dart';

class TabSwitcherSheet extends StatelessWidget {
  const TabSwitcherSheet({
    super.key,
    required this.tabs,
    required this.activeTabId,
    required this.onSelectTab,
    required this.onCloseTab,
    required this.onCloseAll,
    required this.onNewTab,
  });

  final List<BrowserTabSession> tabs;
  final String? activeTabId;
  final ValueChanged<String> onSelectTab;
  final ValueChanged<String> onCloseTab;
  final VoidCallback onCloseAll;
  final VoidCallback onNewTab;

  static const double _tabTileHeight = 68;
  static const double _tabTileSpacing = 8;
  static const double _tabListItemExtent = _tabTileHeight + _tabTileSpacing;
  static const double _sheetMaxHeightFactor = 0.35;
  static const BorderRadius _tileBorderRadius = BorderRadius.all(
    Radius.circular(22),
  );
  static const BorderRadius _iconBorderRadius = BorderRadius.all(
    Radius.circular(16),
  );

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final activeBackgroundColor = colorScheme.primaryContainer.withValues(
      alpha: 0.5,
    );
    final activeBorderColor = colorScheme.primary.withValues(alpha: 0.4);
    final inactiveBorderColor = colorScheme.outlineVariant.withValues(
      alpha: 0.4,
    );
    final activeIconBackgroundColor = colorScheme.primary.withValues(
      alpha: 0.1,
    );

    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * _sheetMaxHeightFactor,
        ),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            // Drag handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Icon(
                    Icons.filter_none_rounded,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '标签页',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${tabs.length}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: '新建标签页',
                    onPressed: onNewTab,
                    style: IconButton.styleFrom(
                      backgroundColor: colorScheme.primaryContainer,
                    ),
                    icon: Icon(Icons.add_rounded, color: colorScheme.primary),
                  ),
                  TextButton(onPressed: onCloseAll, child: const Text('关闭全部')),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                itemExtent: _tabListItemExtent,
                cacheExtent: 0,
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: false,
                itemCount: tabs.length,
                itemBuilder: (context, index) {
                  final tab = tabs[index];
                  final isActive = tab.id == activeTabId;

                  return Padding(
                    key: ValueKey(tab.id),
                    padding: const EdgeInsets.only(bottom: _tabTileSpacing),
                    child: RepaintBoundary(
                      child: Material(
                        color: isActive
                            ? activeBackgroundColor
                            : colorScheme.surfaceContainerHighest,
                        shape: RoundedRectangleBorder(
                          borderRadius: _tileBorderRadius,
                          side: BorderSide(
                            color: isActive
                                ? activeBorderColor
                                : inactiveBorderColor,
                            width: isActive ? 1.5 : 1,
                          ),
                        ),
                        child: InkWell(
                          onTap: () => onSelectTab(tab.id),
                          borderRadius: _tileBorderRadius,
                          child: SizedBox(
                            height: _tabTileHeight,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: isActive
                                          ? activeIconBackgroundColor
                                          : colorScheme.surfaceContainerLow,
                                      borderRadius: _iconBorderRadius,
                                    ),
                                    child: Icon(
                                      tab.isLoading
                                          ? Icons.hourglass_top
                                          : Icons.language,
                                      size: 18,
                                      color: isActive
                                          ? colorScheme.primary
                                          : colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          tab.displayTitle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: isActive
                                                ? FontWeight.w600
                                                : FontWeight.w500,
                                            color: colorScheme.onSurface,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          tab.url,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: '关闭标签页',
                                    onPressed: () => onCloseTab(tab.id),
                                    icon: Icon(
                                      Icons.close_rounded,
                                      size: 18,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
