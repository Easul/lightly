import 'dart:convert';

class BrowserSiteCompatibilityScript {
  const BrowserSiteCompatibilityScript._();

  static const defaultDesktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  static String? desktopViewportOverrideForUrl(
    String? rawUrl, {
    String desktopUserAgent = defaultDesktopUserAgent,
  }) {
    final uri = Uri.tryParse(rawUrl ?? '');
    final scheme = uri?.scheme.toLowerCase() ?? '';
    if (scheme != 'http' && scheme != 'https') {
      return null;
    }
    final effectiveUserAgent = desktopUserAgent.trim().isEmpty
        ? defaultDesktopUserAgent
        : desktopUserAgent.trim();
    return _desktopViewportSource(effectiveUserAgent);
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

  static String _desktopViewportSource(String desktopUserAgent) {
    final encodedUserAgent = jsonEncode(desktopUserAgent);
    final encodedPlatform = jsonEncode(
      _desktopClientHintPlatform(desktopUserAgent),
    );
    final encodedNavigatorPlatform = jsonEncode(
      _desktopNavigatorPlatform(desktopUserAgent),
    );
    return '''
      (function() {
        var minimumDesktopWidth = 980;
        var desktopUserAgent = $encodedUserAgent;
        var desktopPlatform = $encodedPlatform;
        var desktopNavigatorPlatform = $encodedNavigatorPlatform;
        var nativeUserAgentData = navigator.userAgentData;

        function defineGetter(target, property, getter) {
          if (!target) {
            return;
          }
          try {
            Object.defineProperty(target, property, {
              configurable: true,
              get: getter
            });
          } catch (_) {}
        }

        function chromeMajorVersion() {
          var match = /(?:Chrome|CriOS)\\/([0-9]+)/.exec(desktopUserAgent);
          return match ? match[1] : '131';
        }

        function desktopBrands() {
          if (nativeUserAgentData && Array.isArray(nativeUserAgentData.brands)) {
            return nativeUserAgentData.brands.map(function(item) {
              return { brand: item.brand, version: item.version };
            });
          }
          var major = chromeMajorVersion();
          return [
            { brand: 'Google Chrome', version: major },
            { brand: 'Chromium', version: major },
            { brand: 'Not A(Brand', version: '24' }
          ];
        }

        function desktopUserAgentData() {
          var brands = desktopBrands();
          return {
            brands: brands,
            mobile: false,
            platform: desktopPlatform,
            getHighEntropyValues: function(hints) {
              var requestedHints = Array.isArray(hints) ? hints : [];
              var nativeValues = nativeUserAgentData &&
                      typeof nativeUserAgentData.getHighEntropyValues === 'function'
                  ? nativeUserAgentData.getHighEntropyValues(requestedHints)
                  : Promise.resolve({});
              return Promise.resolve(nativeValues).then(function(values) {
                var result = Object.assign({}, values || {});
                result.brands = brands;
                result.mobile = false;
                result.platform = desktopPlatform;
                if (requestedHints.indexOf('model') !== -1) {
                  result.model = '';
                }
                return result;
              });
            },
            toJSON: function() {
              return {
                brands: brands,
                mobile: false,
                platform: desktopPlatform
              };
            }
          };
        }

        function applyDesktopNavigator() {
          var navProto = window.Navigator && window.Navigator.prototype;
          var userAgentData = desktopUserAgentData();
          [window.navigator, navProto].forEach(function(target) {
            defineGetter(target, 'userAgent', function() {
              return desktopUserAgent;
            });
            defineGetter(target, 'platform', function() {
              return desktopNavigatorPlatform;
            });
            defineGetter(target, 'userAgentData', function() {
              return userAgentData;
            });
          });
        }

        function desktopViewportContent() {
          var currentWidth = Math.max(
            window.innerWidth || 0,
            document.documentElement
              ? document.documentElement.clientWidth || 0
              : 0
          );
          var desktopWidth = Math.max(minimumDesktopWidth, currentWidth);
          return 'width=' + desktopWidth + ', user-scalable=yes';
        }

        function applyDesktopViewport() {
          if (!document.documentElement) {
            return;
          }
          var head = document.head ||
              document.getElementsByTagName('head')[0] ||
              document.documentElement;
          var metas = Array.prototype.slice.call(
            document.querySelectorAll('meta[name="viewport" i]')
          );
          if (metas.length === 0) {
            var meta = document.createElement('meta');
            meta.name = 'viewport';
            meta.setAttribute('data-lightly-desktop-viewport', 'true');
            head.appendChild(meta);
            metas.push(meta);
          }
          var content = desktopViewportContent();
          metas.forEach(function(meta) {
            if (!meta.hasAttribute('data-lightly-original-content')) {
              meta.setAttribute(
                'data-lightly-original-content',
                meta.getAttribute('content') || ''
              );
            }
            if (meta.getAttribute('content') !== content) {
              meta.setAttribute('content', content);
            }
          });
        }

        function applyDesktopEnvironment() {
          applyDesktopNavigator();
          applyDesktopViewport();
        }

        function observeViewportChanges() {
          if (window.__lightlyDesktopViewportObserver || !window.MutationObserver) {
            return;
          }
          var target = document.head || document.documentElement;
          if (!target) {
            return;
          }
          var scheduled = false;
          var observer = new MutationObserver(function() {
            if (scheduled) {
              return;
            }
            scheduled = true;
            requestAnimationFrame(function() {
              scheduled = false;
              applyDesktopViewport();
            });
          });
          observer.observe(target, {
            subtree: true,
            childList: true,
            attributes: true,
            attributeFilter: ['content']
          });
          window.__lightlyDesktopViewportObserver = observer;
        }

        window.__lightlyApplyDesktopEnvironment = applyDesktopEnvironment;
        applyDesktopEnvironment();
        observeViewportChanges();
        if (document.readyState === 'loading') {
          document.addEventListener(
            'DOMContentLoaded',
            function() {
              applyDesktopEnvironment();
              observeViewportChanges();
            },
            { once: true }
          );
        }
        window.addEventListener('pageshow', applyDesktopEnvironment);
      })();
    ''';
  }

  static String _desktopClientHintPlatform(String userAgent) {
    if (userAgent.contains('Windows')) {
      return 'Windows';
    }
    if (userAgent.contains('Macintosh') || userAgent.contains('Mac OS X')) {
      return 'macOS';
    }
    if (userAgent.contains('CrOS')) {
      return 'Chrome OS';
    }
    return 'Linux';
  }

  static String _desktopNavigatorPlatform(String userAgent) {
    if (userAgent.contains('Windows')) {
      return 'Win32';
    }
    if (userAgent.contains('Macintosh') || userAgent.contains('Mac OS X')) {
      return 'MacIntel';
    }
    return 'Linux x86_64';
  }

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
