import '../browser/utils/browser_popup_filter.dart';

class BrowserPageUrlFilterHelper {
  const BrowserPageUrlFilterHelper();

  bool isWebScheme(String? scheme) {
    return BrowserPopupFilter.isWebScheme(scheme);
  }

  bool shouldSuppressPopupUrl(String? url) {
    return BrowserPopupFilter.shouldSuppressPopupUrl(url);
  }
}
