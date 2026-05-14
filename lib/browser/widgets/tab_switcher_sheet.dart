import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
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
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                shrinkWrap: true,
                itemCount: tabs.length,
                separatorBuilder: (BuildContext context, int index) =>
                    const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final tab = tabs[index];
                  final isActive = tab.id == activeTabId;

                  return Material(
                    color: isActive
                        ? colorScheme.primaryContainer.withValues(alpha: 0.5)
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(22),
                    child: InkWell(
                      onTap: () => onSelectTab(tab.id),
                      borderRadius: BorderRadius.circular(22),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: AppTheme.softShadow(),
                          border: isActive
                              ? Border.all(
                                  color: colorScheme.primary.withValues(
                                    alpha: 0.4,
                                  ),
                                  width: 1.5,
                                )
                              : null,
                        ),
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
                                    ? colorScheme.primary.withValues(alpha: 0.1)
                                    : colorScheme.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(16),
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
                                crossAxisAlignment: CrossAxisAlignment.start,
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
