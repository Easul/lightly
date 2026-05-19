import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_toast.dart';
import '../widgets/app_drawer.dart';
import '../calculator/expression_evaluator.dart';
import '../calculator/calculation_history.dart';
import '../calculator/history_service.dart';

class CalculatorPage extends StatefulWidget {
  const CalculatorPage({super.key});

  @override
  State<CalculatorPage> createState() => _CalculatorPageState();
}

class _CalculatorPageState extends State<CalculatorPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final HistoryService _historyService = HistoryService();
  final TextEditingController _expressionController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _expressionFocusNode = FocusNode();

  List<CalculationHistory> _history = [];
  List<CalculationHistory> _filteredHistory = [];
  String _result = '';
  String _errorMessage = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    _searchController.addListener(_filterHistory);
  }

  void _onTabChanged() {
    if (_tabController.index == 1) {
      _loadHistory();
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _expressionController.dispose();
    _searchController.dispose();
    _expressionFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });
    try {
      final history = await _historyService.loadHistory();
      if (!mounted) return;
      setState(() {
        _history = history;
        _filteredHistory = history;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _history = [];
        _filteredHistory = [];
        _isLoading = false;
      });
    }
  }

  void _filterHistory() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredHistory = _history.where((entry) {
        return entry.expression.toLowerCase().contains(query) ||
            entry.result.toLowerCase().contains(query) ||
            entry.note.toLowerCase().contains(query);
      }).toList();
    });
  }

  String _normalizeInputFragment(String input) {
    return input.replaceAll('（', '(').replaceAll('）', ')');
  }

  void _insertAtSelection(String input) {
    final normalizedInput = _normalizeInputFragment(input);
    final value = _expressionController.value;
    final text = value.text;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: text.length);
    final start = selection.start < 0 ? text.length : selection.start;
    final end = selection.end < 0 ? text.length : selection.end;
    final replaced = text.replaceRange(start, end, normalizedInput);
    final caretOffset = start + normalizedInput.length;

    _expressionController.value = TextEditingValue(
      text: replaced,
      selection: TextSelection.collapsed(offset: caretOffset),
    );
    _expressionFocusNode.requestFocus();
  }

  void _onNumberPressed(String number) {
    _insertAtSelection(number);
  }

  void _onOperatorPressed(String operator) {
    _insertAtSelection(operator);
  }

  void _onClearPressed() {
    _expressionController.clear();
    setState(() {
      _result = '';
      _errorMessage = '';
    });
  }

  void _onDeletePressed() {
    final value = _expressionController.value;
    final text = value.text;
    if (text.isEmpty) {
      return;
    }

    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: text.length);
    final start = selection.start < 0 ? text.length : selection.start;
    final end = selection.end < 0 ? text.length : selection.end;

    if (start != end) {
      _expressionController.value = TextEditingValue(
        text: text.replaceRange(start, end, ''),
        selection: TextSelection.collapsed(offset: start),
      );
    } else if (start > 0) {
      final deleteIndex = start - 1;
      _expressionController.value = TextEditingValue(
        text: text.replaceRange(deleteIndex, start, ''),
        selection: TextSelection.collapsed(offset: deleteIndex),
      );
    }

    _expressionFocusNode.requestFocus();
  }

  Future<void> _onCalculatePressed() async {
    final expression = _expressionController.text.trim();
    if (expression.isEmpty) return;

    try {
      final result = ExpressionEvaluator.evaluate(expression);
      final resultStr = result == result.toInt()
          ? result.toInt().toString()
          : result
                .toStringAsFixed(8)
                .replaceAll(RegExp(r'0*$'), '')
                .replaceAll(RegExp(r'\.$'), '');

      setState(() {
        _result = resultStr;
        _errorMessage = '';
      });

      await _saveToHistory(expression, resultStr);
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('FormatException: ', '');
        _result = '';
      });
    }
  }

  Future<void> _saveToHistory(String expression, String result) async {
    final entry = CalculationHistory(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      expression: expression,
      result: result,
      createdAt: DateTime.now(),
    );
    await _historyService.saveEntry(entry);
    // 只有当在历史 Tab 时才立即刷新，否则不刷新（切换到历史 Tab 时会自动加载）
    if (_tabController.index == 1 && mounted) {
      await _loadHistory();
    }
  }

  Future<void> _updateNote(String id, String note) async {
    await _historyService.updateNote(id, note);
    await _loadHistory();
  }

  Future<void> _deleteEntry(String id) async {
    final history = await _historyService.loadHistory();
    final updated = history.where((e) => e.id != id).toList();
    await _historyService.clearHistory();
    for (final entry in updated.reversed) {
      await _historyService.saveEntry(entry);
    }
    await _loadHistory();
  }

  Future<void> _clearAllHistory() async {
    await _historyService.clearHistory();
    await _loadHistory();
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    unawaited(AppToast.show('已复制到剪贴板'));
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildCalculatorTab() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compactLayout = constraints.maxHeight < 640;
        final resultFontSize = compactLayout ? 28.0 : 32.0;
        final buttonFontSize = compactLayout ? 20.0 : 24.0;
        final buttonPadding = compactLayout ? 14.0 : 18.0;
        final blockSpacing = compactLayout ? 12.0 : 16.0;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // Expression input
              TextField(
                focusNode: _expressionFocusNode,
                controller: _expressionController,
                decoration: InputDecoration(
                  labelText: '表达式',
                  hintText: '例如: 1+2*3 或 (4+5)*6',
                  prefixIcon: const Icon(Icons.edit),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: _onClearPressed,
                  ),
                ),
                style: const TextStyle(fontSize: 20),
                onSubmitted: (_) => _onCalculatePressed(),
                contextMenuBuilder: _buildChineseContextMenu,
              ),
              SizedBox(height: blockSpacing),
              // Result display
              if (_result.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.24),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '结果:',
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _result,
                        style: TextStyle(
                          fontSize: resultFontSize,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              if (_result.isNotEmpty) SizedBox(height: blockSpacing),
              if (_errorMessage.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.error.withValues(alpha: 0.28),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '错误:',
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _errorMessage,
                        style: TextStyle(
                          fontSize: 16,
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              if (_errorMessage.isNotEmpty) SizedBox(height: blockSpacing),
              // Quick buttons
              Column(
                children: [
                  Row(
                    children: [
                      _buildButton(
                        '7',
                        fontSize: buttonFontSize,
                        verticalPadding: buttonPadding,
                      ),
                      _buildButton(
                        '8',
                        fontSize: buttonFontSize,
                        verticalPadding: buttonPadding,
                      ),
                      _buildButton(
                        '9',
                        fontSize: buttonFontSize,
                        verticalPadding: buttonPadding,
                      ),
                      _buildButton(
                        '÷',
                        onPressed: () => _onOperatorPressed('/'),
                        fontSize: buttonFontSize,
                        verticalPadding: buttonPadding,
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      _buildButton(
                        '4',
                        fontSize: buttonFontSize,
                        verticalPadding: buttonPadding,
                      ),
                      _buildButton(
                        '5',
                        fontSize: buttonFontSize,
                        verticalPadding: buttonPadding,
                      ),
                      _buildButton(
                        '6',
                        fontSize: buttonFontSize,
                        verticalPadding: buttonPadding,
                      ),
                      _buildButton(
                        '×',
                        onPressed: () => _onOperatorPressed('*'),
                        fontSize: buttonFontSize,
                        verticalPadding: buttonPadding,
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      _buildButton(
                        '1',
                        fontSize: buttonFontSize,
                        verticalPadding: buttonPadding,
                      ),
                      _buildButton(
                        '2',
                        fontSize: buttonFontSize,
                        verticalPadding: buttonPadding,
                      ),
                      _buildButton(
                        '3',
                        fontSize: buttonFontSize,
                        verticalPadding: buttonPadding,
                      ),
                      _buildButton(
                        '-',
                        onPressed: () => _onOperatorPressed('-'),
                        fontSize: buttonFontSize,
                        verticalPadding: buttonPadding,
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      _buildButton(
                        '0',
                        flex: 2,
                        fontSize: buttonFontSize,
                        verticalPadding: buttonPadding,
                      ),
                      _buildButton(
                        '.',
                        onPressed: () => _onOperatorPressed('.'),
                        fontSize: buttonFontSize,
                        verticalPadding: buttonPadding,
                      ),
                      _buildButton(
                        '+',
                        onPressed: () => _onOperatorPressed('+'),
                        fontSize: buttonFontSize,
                        verticalPadding: buttonPadding,
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      _buildButton(
                        '(',
                        onPressed: () => _onOperatorPressed('('),
                        fontSize: buttonFontSize,
                        verticalPadding: buttonPadding,
                      ),
                      _buildButton(
                        ')',
                        onPressed: () => _onOperatorPressed(')'),
                        fontSize: buttonFontSize,
                        verticalPadding: buttonPadding,
                      ),
                      _buildButton(
                        '⌫',
                        onPressed: _onDeletePressed,
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.secondaryContainer,
                        fontSize: buttonFontSize,
                        verticalPadding: buttonPadding,
                      ),
                      _buildButton(
                        '=',
                        onPressed: _onCalculatePressed,
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        textColor: Theme.of(context).colorScheme.onPrimary,
                        fontSize: buttonFontSize,
                        verticalPadding: buttonPadding,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildButton(
    String text, {
    VoidCallback? onPressed,
    Color? backgroundColor,
    Color? textColor,
    int flex = 1,
    double fontSize = 24,
    double verticalPadding = 18,
  }) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.all(4.0),
        child: ElevatedButton(
          onPressed: onPressed ?? () => _onNumberPressed(text),
          style: ElevatedButton.styleFrom(
            backgroundColor:
                backgroundColor ??
                Theme.of(context).colorScheme.surfaceContainerHighest,
            foregroundColor:
                textColor ?? Theme.of(context).colorScheme.onSurface,
            padding: EdgeInsets.symmetric(vertical: verticalPadding),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryTab() {
    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              labelText: '搜索历史',
              hintText: '搜索表达式、结果或备注',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        // History list with clear button at the bottom
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _filteredHistory.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.history,
                        size: 64,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _searchController.text.isEmpty ? '暂无计算历史' : '未找到匹配的记录',
                        style: TextStyle(
                          fontSize: 16,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                  itemCount:
                      _filteredHistory.length + (_history.isNotEmpty ? 1 : 0),
                  itemBuilder: (context, index) {
                    // Clear all button as the last item
                    if (_history.isNotEmpty &&
                        index == _filteredHistory.length) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 8.0, bottom: 24.0),
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('确认清空'),
                                content: const Text('确定要清空所有历史记录吗？此操作不可恢复。'),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(false),
                                    child: const Text('取消'),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(true),
                                    child: const Text('清空'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed == true) {
                              await _clearAllHistory();
                            }
                          },
                          icon: const Icon(Icons.delete_forever),
                          label: const Text('清空历史'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.errorContainer,
                            foregroundColor: Theme.of(
                              context,
                            ).colorScheme.onErrorContainer,
                            minimumSize: const Size(double.infinity, 48),
                          ),
                        ),
                      );
                    }
                    final entry = _filteredHistory[index];
                    return Dismissible(
                      key: Key(entry.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 16),
                        color: Theme.of(context).colorScheme.error,
                        child: Icon(
                          Icons.delete,
                          color: Theme.of(context).colorScheme.onError,
                        ),
                      ),
                      confirmDismiss: (_) async {
                        return await showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('确认删除'),
                            content: const Text('确定要删除这条记录吗？'),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(false),
                                child: const Text('取消'),
                              ),
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(true),
                                child: const Text('删除'),
                              ),
                            ],
                          ),
                        );
                      },
                      onDismissed: (_) => _deleteEntry(entry.id),
                      child: Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(
                            '${entry.expression} = ${entry.result}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_formatDateTime(entry.createdAt)),
                              if (entry.note.isNotEmpty)
                                Text(
                                  '备注: ${entry.note}',
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                ),
                            ],
                          ),
                          onTap: () => _showNoteDialog(entry),
                          onLongPress: () => _showCopyMenu(entry),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _showNoteDialog(CalculationHistory entry) {
    final noteController = TextEditingController(text: entry.note);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑备注'),
        content: TextField(
          controller: noteController,
          decoration: const InputDecoration(
            labelText: '备注',
            hintText: '输入备注信息',
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              final note = noteController.text;
              Navigator.of(context).pop();
              await _updateNote(entry.id, note);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _showCopyMenu(CalculationHistory entry) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('复制表达式'),
              onTap: () {
                _copyToClipboard(entry.expression);
                Navigator.of(context).pop();
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_all),
              title: const Text('复制结果'),
              onTap: () {
                _copyToClipboard(entry.result);
                Navigator.of(context).pop();
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('复制完整表达式'),
              onTap: () {
                _copyToClipboard('${entry.expression} = ${entry.result}');
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('计算器'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.calculate), text: '计算器'),
            Tab(icon: Icon(Icons.history), text: '历史'),
          ],
        ),
      ),
      drawer: const AppDrawer(),
      body: TabBarView(
        controller: _tabController,
        children: [_buildCalculatorTab(), _buildHistoryTab()],
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
