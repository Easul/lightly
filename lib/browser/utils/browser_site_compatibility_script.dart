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
    return _desktopEnvironmentSource(effectiveUserAgent);
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

  static String _desktopEnvironmentSource(String desktopUserAgent) {
    final encodedUserAgent = jsonEncode(desktopUserAgent);
    return '''
      (function() {
        var desktopWidth = 1366;
        var desktopHeight = 768;
        var desktopUserAgent = $encodedUserAgent;
        var content =
          'width=' + desktopWidth +
          ', initial-scale=1.0, minimum-scale=0.1, maximum-scale=5.0, user-scalable=yes';

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

        function desktopUserAgentData() {
          var major = chromeMajorVersion();
          var brands = [
            { brand: 'Google Chrome', version: major },
            { brand: 'Chromium', version: major },
            { brand: 'Not A(Brand', version: '24' }
          ];
          return {
            brands: brands,
            mobile: false,
            platform: 'Windows',
            getHighEntropyValues: function(hints) {
              var values = {
                brands: brands,
                mobile: false,
                platform: 'Windows',
                architecture: 'x86',
                bitness: '64',
                model: '',
                platformVersion: '10.0.0',
                uaFullVersion: major + '.0.0.0',
                fullVersionList: brands
              };
              var result = {};
              (hints || []).forEach(function(hint) {
                if (Object.prototype.hasOwnProperty.call(values, hint)) {
                  result[hint] = values[hint];
                }
              });
              return Promise.resolve(result);
            },
            toJSON: function() {
              return { brands: brands, mobile: false, platform: 'Windows' };
            }
          };
        }

        function applyDesktopNavigator() {
          var navProto = window.Navigator && window.Navigator.prototype;
          var appVersion = desktopUserAgent.replace(/^Mozilla\\//, '');
          var userAgentData = desktopUserAgentData();
          [
            window.navigator,
            navProto
          ].forEach(function(target) {
            defineGetter(target, 'userAgent', function() {
              return desktopUserAgent;
            });
            defineGetter(target, 'appVersion', function() {
              return appVersion;
            });
            defineGetter(target, 'platform', function() {
              return 'Win32';
            });
            defineGetter(target, 'vendor', function() {
              return 'Google Inc.';
            });
            defineGetter(target, 'maxTouchPoints', function() {
              return 0;
            });
            defineGetter(target, 'userAgentData', function() {
              return userAgentData;
            });
          });
        }

        function applyDesktopScreen() {
          [
            window.screen,
            window.Screen && window.Screen.prototype
          ].forEach(function(target) {
            defineGetter(target, 'width', function() {
              return desktopWidth;
            });
            defineGetter(target, 'availWidth', function() {
              return desktopWidth;
            });
            defineGetter(target, 'height', function() {
              return desktopHeight;
            });
            defineGetter(target, 'availHeight', function() {
              return desktopHeight - 40;
            });
          });
          defineGetter(window, 'outerWidth', function() {
            return desktopWidth;
          });
          defineGetter(window, 'outerHeight', function() {
            return desktopHeight;
          });
          defineGetter(window, 'innerWidth', function() {
            return Math.max(desktopWidth, document.documentElement.clientWidth || 0);
          });
        }

        function evaluateDesktopMedia(query) {
          var groups = String(query || '').toLowerCase().split(',');
          var anyEvaluated = false;
          for (var i = 0; i < groups.length; i += 1) {
            var group = groups[i];
            var matched = true;
            var evaluated = false;

            group.replace(
              /\\(\\s*(min|max)-(device-)?width\\s*:\\s*([0-9.]+)px\\s*\\)/g,
              function(_, bound, _device, value) {
                evaluated = true;
                var width = parseFloat(value);
                if (bound === 'min') {
                  matched = matched && desktopWidth >= width;
                } else {
                  matched = matched && desktopWidth <= width;
                }
                return _;
              }
            );

            if (/\\(\\s*(any-)?pointer\\s*:\\s*coarse\\s*\\)/.test(group)) {
              evaluated = true;
              matched = false;
            }
            if (/\\(\\s*(any-)?pointer\\s*:\\s*fine\\s*\\)/.test(group)) {
              evaluated = true;
              matched = matched && true;
            }
            if (/\\(\\s*(any-)?hover\\s*:\\s*none\\s*\\)/.test(group)) {
              evaluated = true;
              matched = false;
            }
            if (/\\(\\s*(any-)?hover\\s*:\\s*hover\\s*\\)/.test(group)) {
              evaluated = true;
              matched = matched && true;
            }
            if (/\\(\\s*orientation\\s*:\\s*portrait\\s*\\)/.test(group)) {
              evaluated = true;
              matched = false;
            }
            if (/\\(\\s*orientation\\s*:\\s*landscape\\s*\\)/.test(group)) {
              evaluated = true;
              matched = matched && true;
            }

            if (evaluated) {
              anyEvaluated = true;
              if (matched) {
                return true;
              }
            }
          }
          return anyEvaluated ? false : null;
        }

        function applyDesktopMatchMedia() {
          if (!window.matchMedia || window.__lightlyDesktopMatchMediaPatched) {
            return;
          }
          var nativeMatchMedia = window.matchMedia.bind(window);
          window.matchMedia = function(query) {
            var mediaQueryList = nativeMatchMedia(query);
            var desktopMatch = evaluateDesktopMedia(query);
            if (desktopMatch === null) {
              return mediaQueryList;
            }
            defineGetter(mediaQueryList, 'matches', function() {
              return desktopMatch;
            });
            return mediaQueryList;
          };
          window.__lightlyDesktopMatchMediaPatched = true;
        }

        function applyDesktopStyle() {
          if (!document.documentElement) {
            return;
          }
          document.documentElement.style.minWidth = '1024px';
          if (document.body) {
            document.body.style.minWidth = '1024px';
          }

          var head = document.head ||
              document.getElementsByTagName('head')[0] ||
              document.documentElement;
          var style = document.getElementById('lightly-desktop-mode-style');
          if (!style) {
            style = document.createElement('style');
            style.id = 'lightly-desktop-mode-style';
            head.appendChild(style);
          }
          style.textContent = [
            'html, body { min-width: 1024px !important; }',
            '@media (hover: none), (pointer: coarse), (max-width: 1023px) {',
            '  html, body { min-width: 1024px !important; }',
            '}'
          ].join('\\n');
        }

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
          applyDesktopStyle();
        }

        function applyDesktopEnvironment() {
          applyDesktopNavigator();
          applyDesktopScreen();
          applyDesktopMatchMedia();
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
