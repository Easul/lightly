class BrowserSiteCompatibilityScript {
  const BrowserSiteCompatibilityScript._();

  static String? desktopViewportOverrideForUrl(String? rawUrl) {
    final uri = Uri.tryParse(rawUrl ?? '');
    final scheme = uri?.scheme.toLowerCase() ?? '';
    if (scheme != 'http' && scheme != 'https') {
      return null;
    }
    return _desktopViewportOverrideSource;
  }

  static String? bottomNavigationFixForUrl(String? rawUrl) {
    final host = Uri.tryParse(rawUrl ?? '')?.host.toLowerCase() ?? '';
    if (_isYouTubeHost(host)) {
      return _wrapStyle('lightly-youtube-bottom-nav-fix', '''
        ytm-pivot-bar-renderer,
        ytm-pivot-bar-item-renderer {
          max-height: 52px !important;
        }
        ytm-pivot-bar-renderer {
          height: 52px !important;
          min-height: 52px !important;
          padding-bottom: 0 !important;
          transform: translateZ(0);
        }
        ytm-app {
          padding-bottom: 0 !important;
        }
      ''');
    }
    if (_isXHost(host)) {
      return _wrapStyle('lightly-x-bottom-nav-fix', '''
        div[data-testid="BottomBar"],
        div[data-testid="BottomBar"] > div {
          max-height: 56px !important;
        }
        div[data-testid="BottomBar"] {
          padding-bottom: 0 !important;
        }
        body {
          overscroll-behavior-y: contain;
        }
      ''');
    }
    return null;
  }

  static bool _isYouTubeHost(String host) {
    return host == 'youtube.com' ||
        host.endsWith('.youtube.com') ||
        host == 'youtu.be' ||
        host.endsWith('.youtu.be');
  }

  static bool _isXHost(String host) {
    return host == 'x.com' ||
        host.endsWith('.x.com') ||
        host == 'twitter.com' ||
        host.endsWith('.twitter.com');
  }

  static const String _desktopViewportOverrideSource = '''
      (function() {
        var content = 'width=1280, initial-scale=1.0, minimum-scale=0.1, maximum-scale=5.0, user-scalable=yes';
        function applyDesktopViewport() {
          if (!document.documentElement) {
            return;
          }
          var head = document.head ||
              document.getElementsByTagName('head')[0] ||
              document.documentElement;
          var meta = document.querySelector('meta[name="viewport"]');
          if (!meta) {
            meta = document.createElement('meta');
            meta.name = 'viewport';
            head.appendChild(meta);
          }
          if (!meta.hasAttribute('data-lightly-original-content')) {
            meta.setAttribute(
              'data-lightly-original-content',
              meta.getAttribute('content') || ''
            );
          }
          if (meta.getAttribute('content') !== content) {
            meta.setAttribute('content', content);
          }
          document.documentElement.style.minWidth = '1024px';
          if (document.body) {
            document.body.style.minWidth = '1024px';
          }
        }
        applyDesktopViewport();
        if (document.readyState === 'loading') {
          document.addEventListener(
            'DOMContentLoaded',
            applyDesktopViewport,
            { once: true }
          );
        }
      })();
    ''';

  static String _wrapStyle(String id, String css) {
    final escapedCss = css
        .replaceAll(r'\', r'\\')
        .replaceAll('`', r'\`')
        .replaceAll(r'$', r'\$');
    return '''
      (function() {
        var id = '$id';
        var style = document.getElementById(id);
        if (!style) {
          style = document.createElement('style');
          style.id = id;
          document.head.appendChild(style);
        }
        style.textContent = `$escapedCss`;
      })();
    ''';
  }
}
