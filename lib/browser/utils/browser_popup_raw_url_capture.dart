import 'dart:convert';

class BrowserPopupRawUrlCapture {
  const BrowserPopupRawUrlCapture._();

  static const initialScript = r'''
    (function() {
      if (window.__lightlyPopupRawCaptureInstalled) {
        return;
      }
      window.__lightlyPopupRawCaptureInstalled = true;

      var entries = [];
      var maxAgeMs = 10000;

      function asString(value) {
        if (typeof value === 'string') {
          return value;
        }
        if (value == null) {
          return '';
        }
        try {
          return String(value);
        } catch (_) {
          return '';
        }
      }

      function resolvedUrl(rawUrl) {
        try {
          return new URL(rawUrl, document.baseURI).href;
        } catch (_) {
          return rawUrl;
        }
      }

      function prune() {
        var cutoff = Date.now() - maxAgeMs;
        entries = entries.filter(function(entry) {
          return entry.createdAt >= cutoff;
        });
      }

      function capture(rawValue, resolvedValue) {
        var rawUrl = asString(rawValue);
        if (!rawUrl || rawUrl === 'about:blank') {
          return;
        }
        prune();
        entries.push({
          rawUrl: rawUrl,
          resolvedUrl: asString(resolvedValue) || resolvedUrl(rawUrl),
          createdAt: Date.now()
        });
        if (entries.length > 12) {
          entries.splice(0, entries.length - 12);
        }
      }

      function comparable(value) {
        var text = asString(value);
        try {
          text = decodeURIComponent(text);
        } catch (_) {}
        return text.toLowerCase();
      }

      function schemeOf(value) {
        var match = /^([a-zA-Z][a-zA-Z0-9+.-]*):/.exec(asString(value));
        return match ? match[1].toLowerCase() : '';
      }

      window.__lightlyTakeRawPopupUrl = function(fallbackUrl) {
        prune();
        var fallbackComparable = comparable(fallbackUrl);
        var index;
        for (index = entries.length - 1; index >= 0; index -= 1) {
          var entry = entries[index];
          if (comparable(entry.rawUrl) === fallbackComparable ||
              comparable(entry.resolvedUrl) === fallbackComparable) {
            entries.splice(index, 1);
            return entry.rawUrl;
          }
        }

        var fallbackScheme = schemeOf(fallbackUrl);
        var recentCutoff = Date.now() - 3000;
        for (index = entries.length - 1; index >= 0; index -= 1) {
          var recentEntry = entries[index];
          if (recentEntry.createdAt < recentCutoff) {
            break;
          }
          if (!fallbackScheme || schemeOf(recentEntry.rawUrl) === fallbackScheme) {
            entries.splice(index, 1);
            return recentEntry.rawUrl;
          }
        }
        return null;
      };

      try {
        var originalOpen = window.open;
        if (typeof originalOpen === 'function') {
          window.open = function(url) {
            capture(url);
            return originalOpen.apply(this, arguments);
          };
        }
      } catch (_) {}

      function captureLinkEvent(event) {
        try {
          var target = event.target;
          if (target && target.nodeType === Node.TEXT_NODE) {
            target = target.parentElement;
          }
          var link = target && target.closest
              ? target.closest('a[href], area[href]')
              : null;
          if (link) {
            capture(link.getAttribute('href'), link.href);
          }
        } catch (_) {}
      }

      document.addEventListener('click', captureLinkEvent, true);
      document.addEventListener('auxclick', captureLinkEvent, true);
    })();
  ''';

  static String takeLatestScript(String fallbackUrl) {
    final encodedFallbackUrl = jsonEncode(fallbackUrl);
    return '''
      (function() {
        if (typeof window.__lightlyTakeRawPopupUrl !== 'function') {
          return null;
        }
        return window.__lightlyTakeRawPopupUrl($encodedFallbackUrl);
      })();
    ''';
  }

  static String? capturedUrlFromResult(dynamic result) {
    if (result is! String || result.isEmpty) {
      return null;
    }
    return result;
  }
}
