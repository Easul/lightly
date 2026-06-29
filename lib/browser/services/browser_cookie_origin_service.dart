import 'package:shared_preferences/shared_preferences.dart';

class BrowserCookieOriginService {
  BrowserCookieOriginService({SharedPreferences? preferences})
    : _preferences = preferences;

  static const String _storageKey = 'browser_cookie_origins_v1';

  SharedPreferences? _preferences;
  Set<String>? _cachedOrigins;

  Future<SharedPreferences> get _prefs async {
    final cached = _preferences;
    if (cached != null) {
      return cached;
    }
    final loaded = await SharedPreferences.getInstance();
    _preferences = loaded;
    return loaded;
  }

  Future<void> recordUrl(String? rawUrl) async {
    final origin = normalizeOrigin(rawUrl);
    if (origin == null) {
      return;
    }
    final origins = await _originSet;
    if (!origins.add(origin)) {
      return;
    }
    final prefs = await _prefs;
    await prefs.setStringList(_storageKey, origins.toList(growable: false));
  }

  Future<List<String>> loadOrigins() async {
    final origins = await _originSet;
    return origins.toList(growable: false);
  }

  Future<void> clearOrigins() async {
    _cachedOrigins = <String>{};
    final prefs = await _prefs;
    await prefs.remove(_storageKey);
  }

  Future<Set<String>> get _originSet async {
    final cached = _cachedOrigins;
    if (cached != null) {
      return cached;
    }
    final prefs = await _prefs;
    final loaded = (prefs.getStringList(_storageKey) ?? const <String>[])
        .map(normalizeOrigin)
        .whereType<String>()
        .toSet();
    _cachedOrigins = loaded;
    return loaded;
  }

  static String? normalizeOrigin(String? rawUrl) {
    if (rawUrl == null || rawUrl.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      return null;
    }
    return uri.origin;
  }
}
