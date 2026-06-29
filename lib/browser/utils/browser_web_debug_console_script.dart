import 'dart:convert';

class BrowserWebDebugConsoleScript {
  const BrowserWebDebugConsoleScript._();

  static const _scriptElementId = 'lightly-eruda-script';
  static const _loadingFlag = '__lightlyErudaLoading';

  static const List<String> _cdnUrls = <String>[
    'https://cdn.jsdelivr.net/npm/eruda',
    'https://unpkg.com/eruda',
  ];

  static bool supportsUrl(String? rawUrl) {
    final scheme = Uri.tryParse(rawUrl ?? '')?.scheme.toLowerCase() ?? '';
    return scheme == 'http' || scheme == 'https';
  }

  static String buildEnableScript() {
    final encodedUrls = jsonEncode(_cdnUrls);
    return '''
      (function() {
        try {
          var scriptId = ${jsonEncode(_scriptElementId)};
          var loadingFlag = ${jsonEncode(_loadingFlag)};
          var sources = $encodedUrls;

          function initEruda() {
            if (!window.eruda || typeof window.eruda.init !== 'function') {
              return 'missing';
            }
            try {
              if (typeof window.eruda.destroy === 'function') {
                window.eruda.destroy();
              }
            } catch (_) {}
            window.eruda.init({ useShadowDom: false });
            return 'ready';
          }

          if (window.eruda && typeof window.eruda.init === 'function') {
            return initEruda();
          }

          if (window[loadingFlag]) {
            return 'loading';
          }

          window[loadingFlag] = true;
          var index = 0;

          function clearLoadingFlag() {
            window[loadingFlag] = false;
          }

          function removeExistingScript() {
            var existing = document.getElementById(scriptId);
            if (existing && existing.parentNode) {
              existing.parentNode.removeChild(existing);
            }
          }

          function loadNext() {
            if (index >= sources.length) {
              clearLoadingFlag();
              return;
            }

            removeExistingScript();
            var script = document.createElement('script');
            script.id = scriptId;
            script.src = sources[index++];
            script.async = true;
            script.onload = function() {
              clearLoadingFlag();
              initEruda();
            };
            script.onerror = function() {
              if (script.parentNode) {
                script.parentNode.removeChild(script);
              }
              loadNext();
            };
            (document.head || document.documentElement).appendChild(script);
          }

          loadNext();
          return 'loading';
        } catch (error) {
          return String(error);
        }
      })();
    ''';
  }

  static String buildDisableScript() {
    return '''
      (function() {
        try {
          var scriptId = ${jsonEncode(_scriptElementId)};
          var loadingFlag = ${jsonEncode(_loadingFlag)};
          if (window.eruda && typeof window.eruda.destroy === 'function') {
            window.eruda.destroy();
          }
          var existing = document.getElementById(scriptId);
          if (existing && existing.parentNode) {
            existing.parentNode.removeChild(existing);
          }
          window[loadingFlag] = false;
          return 'disabled';
        } catch (error) {
          return String(error);
        }
      })();
    ''';
  }
}
