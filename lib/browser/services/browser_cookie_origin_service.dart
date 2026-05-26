import 'package:shared_preferences/shared_preferences.dart';

class BrowserCookieOriginService {
  BrowserCookieOriginService({SharedPreferences? preferences})
    : _preferences = preferences;

  static const String _storageKey = 'browser_cookie_origins_v1';

  SharedPreferences? _preferences;

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
    final prefs = await _prefs;
    final origins = prefs.getStringList(_storageKey) ?? const <String>[];
    if (origins.contains(origin)) {
      return;
    }
    await prefs.setStringList(_storageKey, <String>[...origins, origin]);
  }

  Future<List<String>> loadOrigins() async {
    final prefs = await _prefs;
    final origins = prefs.getStringList(_storageKey) ?? const <String>[];
    return origins
        .map(normalizeOrigin)
        .whereType<String>()
        .toSet()
        .toList(growable: false);
  }

  Future<void> clearOrigins() async {
    final prefs = await _prefs;
    await prefs.remove(_storageKey);
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
