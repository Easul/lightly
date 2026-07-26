import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_toast.dart';
import '../features/calculator/calculation_history.dart';
import '../features/calculator/calculator_action_sheets.dart';
import '../features/calculator/calculator_history_widgets.dart';
import '../features/calculator/calculator_input_tab.dart';
import '../features/calculator/calculator_text_selection_toolbar.dart';
import '../features/calculator/expression_evaluator.dart';
import '../features/calculator/history_service.dart';

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

  Widget _buildCalculatorTab() {
    return CalculatorInputTab(
      expressionController: _expressionController,
      expressionFocusNode: _expressionFocusNode,
      result: _result,
      errorMessage: _errorMessage,
      onClearPressed: _onClearPressed,
      onCalculatePressed: () => unawaited(_onCalculatePressed()),
      onNumberPressed: _onNumberPressed,
      onOperatorPressed: _onOperatorPressed,
      onDeletePressed: _onDeletePressed,
      contextMenuBuilder: buildChineseTextSelectionToolbar,
    );
  }

  Widget _buildHistoryTab() {
    return CalculatorHistoryTab(
      searchController: _searchController,
      isLoading: _isLoading,
      filteredHistory: _filteredHistory,
      hasHistory: _history.isNotEmpty,
      onClearAllHistory: _clearAllHistory,
      onDeleteEntry: _deleteEntry,
      onEntryTap: _showNoteDialog,
      onEntryLongPress: _showCopyMenu,
    );
  }

  void _showNoteDialog(CalculationHistory entry) {
    unawaited(
      showCalculationNoteDialog(
        context: context,
        entry: entry,
        onSaveNote: _updateNote,
      ),
    );
  }

  void _showCopyMenu(CalculationHistory entry) {
    unawaited(
      showCalculationCopyMenu(
        context: context,
        entry: entry,
        onCopy: _copyToClipboard,
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
      body: TabBarView(
        controller: _tabController,
        children: [_buildCalculatorTab(), _buildHistoryTab()],
      ),
    );
  }
}
