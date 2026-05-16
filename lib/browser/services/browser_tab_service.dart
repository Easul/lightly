import 'dart:async';
import 'dart:convert';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/browser_tab_session.dart';

class BrowserTabService {
  BrowserTabService._internal() : _maxTabs = 8;

  BrowserTabService.test({int maxTabs = 8}) : _maxTabs = maxTabs;

  static final BrowserTabService _instance = BrowserTabService._internal();
  factory BrowserTabService() => _instance;

  static const String _prefsKey = 'browser_tab_sessions_v1';

  final int _maxTabs;

  int get maxTabs => _maxTabs;

  final List<BrowserTabSession> _tabs = <BrowserTabSession>[];
  final List<String> _usageOrder = <String>[];
  final Map<String, DateTime> _lastActiveTimes = <String, DateTime>{};
  String? _activeTabId;
  int _nextId = 0;
  String _fallbackUrl = 'https://www.google.com';

  List<BrowserTabSession> get tabs =>
      List<BrowserTabSession>.unmodifiable(_tabs);

  BrowserTabSession? get activeTab {
    if (_activeTabId == null) {
      return _tabs.isEmpty ? null : _tabs.first;
    }
    for (final tab in _tabs) {
      if (tab.id == _activeTabId) {
        return tab;
      }
    }
    return _tabs.isEmpty ? null : _tabs.first;
  }

  int get tabCount => _tabs.length;

  void initialize(String initialUrl) {
    _fallbackUrl = initialUrl;
    if (_tabs.isNotEmpty) {
      return;
    }
    final tab = _buildTab(url: initialUrl);
    _tabs.add(tab);
    _activeTabId = tab.id;
    _touch(tab.id);
  }

  void setFallbackUrl(String url) {
    _fallbackUrl = url;
  }

  BrowserTabSession openTab({
    required String url,
    String title = '',
    bool activate = true,
    bool isExternallyOpened = false,
  }) {
    final tab = _buildTab(
      url: url,
      title: title,
      isExternallyOpened: isExternallyOpened,
    );
    _tabs.add(tab);
    if (activate) {
      _activeTabId = tab.id;
    }
    _touch(tab.id);
    _evictIfNeeded(protectedId: tab.id);
    return tab;
  }

  BrowserTabSession? tabById(String tabId) {
    final index = _indexOf(tabId);
    if (index == -1) {
      return null;
    }
    return _tabs[index];
  }

  bool activateTab(String tabId) {
    final index = _indexOf(tabId);
    if (index == -1) {
      return false;
    }
    _activeTabId = tabId;
    _touch(tabId);
    return true;
  }

  int trimInactiveKeepAlives({
    Duration inactiveThreshold = const Duration(seconds: 45),
    int maxRetainedBackgroundTabs = 1,
  }) {
    if (_tabs.length <= 1) {
      return 0;
    }

    final now = DateTime.now();
    final activeId = _activeTabId;
    final backgroundTabs = _tabs.where((tab) => tab.id != activeId).toList()
      ..sort((a, b) {
        final aTime =
            _lastActiveTimes[a.id] ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime =
            _lastActiveTimes[b.id] ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });

    final retainedIds = <String>{};
    for (final tab in backgroundTabs) {
      final lastActive = _lastActiveTimes[tab.id];
      if (retainedIds.length >= maxRetainedBackgroundTabs ||
          lastActive == null) {
        continue;
      }
      if (now.difference(lastActive) <= inactiveThreshold) {
        retainedIds.add(tab.id);
      }
    }

    var trimmedCount = 0;
    for (var i = 0; i < _tabs.length; i++) {
      final tab = _tabs[i];
      if (tab.id == activeId ||
          tab.keepAlive == null ||
          retainedIds.contains(tab.id)) {
        continue;
      }
      _disposeKeepAlive(tab.keepAlive);
      _tabs[i] = tab.copyWith(clearKeepAlive: true);
      trimmedCount += 1;
    }

    return trimmedCount;
  }

  int trimAllBackgroundKeepAlives() {
    return trimInactiveKeepAlives(
      inactiveThreshold: Duration.zero,
      maxRetainedBackgroundTabs: 0,
    );
  }

  int trimKeepAlivesForOverlay() {
    return trimInactiveKeepAlives(
      inactiveThreshold: const Duration(minutes: 2),
      maxRetainedBackgroundTabs: 2,
    );
  }

  bool ensureKeepAlive(String tabId) {
    final index = _indexOf(tabId);
    if (index == -1) {
      return false;
    }
    final current = _tabs[index];
    if (current.keepAlive != null || !current.url.startsWith('http')) {
      return false;
    }
    _tabs[index] = current.copyWith(keepAlive: InAppWebViewKeepAlive());
    return true;
  }

  bool resetKeepAlive(String tabId, {bool recreate = false}) {
    final index = _indexOf(tabId);
    if (index == -1) {
      return false;
    }
    final current = _tabs[index];
    _disposeKeepAlive(current.keepAlive);
    _tabs[index] = current.copyWith(
      keepAlive: recreate && current.url.startsWith('http')
          ? InAppWebViewKeepAlive()
          : null,
      clearKeepAlive: !recreate,
    );
    return true;
  }

  bool updateTab(
    String tabId, {
    String? url,
    String? title,
    bool? isLoading,
    bool? canGoBack,
    bool? canGoForward,
    double? scrollPosition,
    bool? isExternallyOpened,
  }) {
    final index = _indexOf(tabId);
    if (index == -1) {
      return false;
    }
    final current = _tabs[index];
    final next = current.copyWith(
      url: url,
      title: title,
      isLoading: isLoading,
      canGoBack: canGoBack,
      canGoForward: canGoForward,
      scrollPosition: scrollPosition,
      isExternallyOpened: isExternallyOpened,
    );
    if (next.url == current.url &&
        next.title == current.title &&
        next.isLoading == current.isLoading &&
        next.canGoBack == current.canGoBack &&
        next.canGoForward == current.canGoForward &&
        next.scrollPosition == current.scrollPosition &&
        next.isExternallyOpened == current.isExternallyOpened) {
      return false;
    }

    _tabs[index] = next;
    return true;
  }

  BrowserTabSession closeTab(String tabId) {
    final index = _indexOf(tabId);
    if (index == -1) {
      return _ensureAtLeastOneTab();
    }
    final removed = _tabs.removeAt(index);
    _usageOrder.remove(tabId);
    _lastActiveTimes.remove(tabId);
    _disposeKeepAlive(removed.keepAlive);

    if (_tabs.isEmpty) {
      final replacement = _buildTab(url: _fallbackUrl);
      _tabs.add(replacement);
      _activeTabId = replacement.id;
      _touch(replacement.id);
      return replacement;
    }

    if (_activeTabId == tabId) {
      _activeTabId = _usageOrder.isNotEmpty ? _usageOrder.last : _tabs.last.id;
    }

    return activeTab!;
  }

  Future<void> saveSessions() async {
    final prefs = await SharedPreferences.getInstance();
    if (_tabs.isEmpty) {
      await prefs.remove(_prefsKey);
      return;
    }
    final persistentTabs = _tabs
        .where((tab) => !tab.isExternallyOpened)
        .toList();
    if (persistentTabs.isEmpty) {
      await prefs.remove(_prefsKey);
      return;
    }
    final persistentActiveIndex = _activeTabId == null
        ? 0
        : persistentTabs
              .indexWhere((t) => t.id == _activeTabId)
              .clamp(0, persistentTabs.length - 1);
    final data = {
      'tabs': persistentTabs
          .map((t) => {'url': t.url, 'title': t.title})
          .toList(),
      'activeIndex': persistentActiveIndex,
    };
    await prefs.setString(_prefsKey, jsonEncode(data));
  }

  Future<void> restoreSessions(String fallbackUrl) async {
    _fallbackUrl = fallbackUrl;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) {
      _createInitialTab(fallbackUrl);
      return;
    }
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final tabList = (data['tabs'] as List<dynamic>?) ?? [];
      final activeIndex =
          (data['activeIndex'] as int?)?.clamp(0, tabList.length - 1) ?? 0;
      _tabs.clear();
      _usageOrder.clear();
      _lastActiveTimes.clear();
      _nextId = 0;
      for (int i = 0; i < tabList.length; i++) {
        final item = tabList[i] as Map<String, dynamic>;
        final url = item['url'] as String? ?? fallbackUrl;
        final title = item['title'] as String? ?? '';
        final tab = _buildTab(url: url, title: title);
        _tabs.add(tab);
        _usageOrder.add(tab.id);
      }
      if (_tabs.isNotEmpty) {
        _activeTabId = _tabs[activeIndex].id;
        _touch(_activeTabId!);
        trimAllBackgroundKeepAlives();
      } else {
        _createInitialTab(fallbackUrl);
      }
    } catch (_) {
      _createInitialTab(fallbackUrl);
    }
  }

  void _createInitialTab(String url) {
    _tabs.clear();
    _usageOrder.clear();
    _lastActiveTimes.clear();
    _nextId = 0;
    final tab = _buildTab(url: url);
    _tabs.add(tab);
    _activeTabId = tab.id;
    _touch(tab.id);
  }

  BrowserTabSession _ensureAtLeastOneTab() {
    if (_tabs.isNotEmpty) {
      return activeTab!;
    }
    final replacement = _buildTab(url: _fallbackUrl);
    _tabs.add(replacement);
    _activeTabId = replacement.id;
    _touch(replacement.id);
    return replacement;
  }

  BrowserTabSession _buildTab({
    required String url,
    String title = '',
    bool isExternallyOpened = false,
  }) {
    _nextId += 1;
    return BrowserTabSession(
      id: 'tab_$_nextId',
      url: url,
      keepAlive: url.startsWith('http') ? InAppWebViewKeepAlive() : null,
      title: title,
      isExternallyOpened: isExternallyOpened,
    );
  }

  void _evictIfNeeded({required String protectedId}) {
    while (_tabs.length > maxTabs) {
      String idToRemove = _usageOrder.isNotEmpty
          ? _usageOrder.first
          : _tabs.first.id;
      if (idToRemove == protectedId && _usageOrder.length > 1) {
        idToRemove = _usageOrder[1];
      }
      final index = _indexOf(idToRemove);
      if (index == -1) {
        _usageOrder.remove(idToRemove);
        continue;
      }
      final removed = _tabs.removeAt(index);
      _usageOrder.remove(idToRemove);
      _disposeKeepAlive(removed.keepAlive);
      if (_activeTabId == idToRemove) {
        _activeTabId = protectedId;
      }
    }
  }

  void _touch(String tabId) {
    _usageOrder.remove(tabId);
    _usageOrder.add(tabId);
    _lastActiveTimes[tabId] = DateTime.now();
  }

  int _indexOf(String tabId) {
    return _tabs.indexWhere((tab) => tab.id == tabId);
  }

  void _disposeKeepAlive(InAppWebViewKeepAlive? keepAlive) {
    if (keepAlive == null || InAppWebViewPlatform.instance == null) {
      return;
    }
    unawaited(InAppWebViewController.disposeKeepAlive(keepAlive));
  }
}
