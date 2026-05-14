import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../services/browser_suggestion_service.dart';

class BrowserAddressBar extends StatefulWidget {
  const BrowserAddressBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.isSecure,
    required this.suggestionService,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
    required this.onEditingComplete,
    this.isLoading = false,
    this.onRefresh,
    this.onSecurityPressed,
    this.currentUrl,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isSecure;
  final BrowserSuggestionService suggestionService;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;
  final VoidCallback onEditingComplete;
  final bool isLoading;
  final VoidCallback? onRefresh;
  final VoidCallback? onSecurityPressed;
  final String? currentUrl;

  @override
  State<BrowserAddressBar> createState() => _BrowserAddressBarState();
}

class _BrowserAddressBarState extends State<BrowserAddressBar> {
  final LayerLink _layerLink = LayerLink();
  final GlobalKey _fieldKey = GlobalKey();

  OverlayEntry? _overlayEntry;
  List<String> _suggestions = const <String>[];
  int _suggestionRequestId = 0;
  late bool _showClearButton;

  @override
  void initState() {
    super.initState();
    _showClearButton = widget.controller.text.isNotEmpty;
    widget.controller.addListener(_handleControllerChanged);
    widget.focusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant BrowserAddressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
    }
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_handleFocusChanged);
      widget.focusNode.addListener(_handleFocusChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    widget.focusNode.removeListener(_handleFocusChanged);
    _removeOverlay();
    super.dispose();
  }

  void _handleControllerChanged() {
    final shouldShowClearButton = widget.controller.text.isNotEmpty;
    if (shouldShowClearButton == _showClearButton || !mounted) {
      return;
    }
    setState(() {
      _showClearButton = shouldShowClearButton;
    });
  }

  void _handleFocusChanged() {
    if (!widget.focusNode.hasFocus) {
      _suggestionRequestId++;
      _suggestions = const <String>[];
      _removeOverlay();
      return;
    }

    _refreshSuggestions(widget.controller.text);
  }

  Future<void> _refreshSuggestions(String query) async {
    final requestId = ++_suggestionRequestId;
    final results = await widget.suggestionService.suggest(query);
    if (!mounted ||
        requestId != _suggestionRequestId ||
        !widget.focusNode.hasFocus) {
      return;
    }

    final normalizedResults = results
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);

    _suggestions = normalizedResults;
    if (_suggestions.isEmpty) {
      _removeOverlay();
      return;
    }

    _showOrUpdateOverlay();
  }

  void _showOrUpdateOverlay() {
    if (_suggestions.isEmpty) {
      _removeOverlay();
      return;
    }

    if (_overlayEntry == null) {
      _overlayEntry = OverlayEntry(builder: _buildOverlay);
      Overlay.of(context, rootOverlay: true).insert(_overlayEntry!);
      return;
    }

    _overlayEntry?.markNeedsBuild();
  }

  Widget _buildOverlay(BuildContext context) {
    final renderBox =
        _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) {
      return const SizedBox.shrink();
    }

    final size = renderBox.size;
    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              widget.focusNode.unfocus();
              _removeOverlay();
            },
          ),
        ),
        CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: Offset(0, size.height + 8),
          child: Material(
            elevation: 0,
            borderRadius: BorderRadius.circular(28),
            color: colorScheme.surfaceContainerHighest,
            shadowColor: colorScheme.shadow.withValues(alpha: 0.08),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: size.width,
                minWidth: size.width,
                maxHeight: 280,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: colorScheme.outlineVariant),
                  boxShadow: AppTheme.softShadow(0.04),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shrinkWrap: true,
                    itemCount: _suggestions.length,
                    separatorBuilder: (context, index) =>
                        Divider(height: 1, color: colorScheme.outlineVariant),
                    itemBuilder: (context, index) {
                      final suggestion = _suggestions[index];
                      final isUrl =
                          suggestion.startsWith('http') ||
                          suggestion.startsWith('file:');

                      return ListTile(
                        dense: true,
                        leading: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: isUrl
                                ? colorScheme.primaryContainer
                                : colorScheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            isUrl
                                ? Icons.history_rounded
                                : Icons.search_rounded,
                            size: 14,
                            color: isUrl
                                ? colorScheme.onPrimaryContainer
                                : colorScheme.onSurfaceVariant,
                          ),
                        ),
                        title: Text(
                          suggestion,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        onTap: () {
                          widget.controller.text = suggestion;
                          widget.controller.selection = TextSelection.collapsed(
                            offset: suggestion.length,
                          );
                          widget.onChanged(suggestion);
                          widget.onSubmitted(suggestion);
                          widget.focusNode.unfocus();
                          _removeOverlay();
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isFocused = widget.focusNode.hasFocus;

    return CompositedTransformTarget(
      link: _layerLink,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          if (!widget.focusNode.hasFocus) {
            widget.focusNode.requestFocus();
          }
        },
        child: Container(
          key: _fieldKey,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            border: Border.all(
              color: isFocused
                  ? colorScheme.primary
                  : colorScheme.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: AppTheme.softShadow(isFocused ? 0.05 : 0.025),
          ),
          child: Row(
            children: [
              const SizedBox(width: 12),
              InkWell(
                onTap: widget.onSecurityPressed,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (child, animation) =>
                        ScaleTransition(scale: animation, child: child),
                    child: Icon(
                      widget.isSecure ? Icons.lock_rounded : Icons.public,
                      key: ValueKey(widget.isSecure),
                      size: 16,
                      color: widget.isSecure
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: const Key('browser-address-bar'),
                  controller: widget.controller,
                  focusNode: widget.focusNode,
                  textInputAction: TextInputAction.go,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.0,
                    color: colorScheme.onSurface,
                  ),
                  textAlignVertical: TextAlignVertical.center,
                  decoration: InputDecoration(
                    hintText: '搜索或输入网址',
                    hintStyle: TextStyle(
                      fontSize: 14,
                      color: colorScheme.onSurfaceVariant,
                      height: 1.0,
                    ),
                    border: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    suffixIcon: _showClearButton
                        ? InkWell(
                            onTap: () {
                              widget.onClear();
                              _refreshSuggestions('');
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Icon(
                                Icons.close_rounded,
                                size: 16,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          )
                        : null,
                  ),
                  onChanged: (value) {
                    widget.onChanged(value);
                    _refreshSuggestions(value);
                  },
                  onEditingComplete: () {
                    widget.onEditingComplete();
                    _removeOverlay();
                  },
                  onSubmitted: (value) {
                    widget.onSubmitted(value);
                    _removeOverlay();
                  },
                  contextMenuBuilder: _buildChineseContextMenu,
                ),
              ),
              if (widget.onRefresh != null)
                InkWell(
                  onTap: () {
                    // If address bar is empty, restore current URL before refresh
                    if (widget.controller.text.isEmpty &&
                        widget.currentUrl != null &&
                        widget.currentUrl!.isNotEmpty) {
                      widget.controller.text = widget.currentUrl!;
                      widget.controller.selection = TextSelection.collapsed(
                        offset: widget.controller.text.length,
                      );
                    }
                    widget.onRefresh!();
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (child, animation) =>
                          ScaleTransition(scale: animation, child: child),
                      child: Icon(
                        widget.isLoading
                            ? Icons.close_rounded
                            : Icons.refresh_rounded,
                        key: ValueKey(widget.isLoading),
                        size: 20,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                )
              else
                const SizedBox(width: 10),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChineseContextMenu(
    BuildContext context,
    EditableTextState editableTextState,
  ) {
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: <ContextMenuButtonItem>[
        if (editableTextState.copyEnabled)
          ContextMenuButtonItem(
            onPressed: () {
              editableTextState.copySelection(SelectionChangedCause.toolbar);
            },
            label: '复制',
          ),
        if (editableTextState.cutEnabled)
          ContextMenuButtonItem(
            onPressed: () {
              editableTextState.cutSelection(SelectionChangedCause.toolbar);
            },
            label: '剪切',
          ),
        if (editableTextState.pasteEnabled)
          ContextMenuButtonItem(
            onPressed: () {
              editableTextState.pasteText(SelectionChangedCause.toolbar);
            },
            label: '粘贴',
          ),
        if (editableTextState.selectAllEnabled)
          ContextMenuButtonItem(
            onPressed: () {
              editableTextState.selectAll(SelectionChangedCause.toolbar);
            },
            label: '全选',
          ),
      ],
    );
  }
}
