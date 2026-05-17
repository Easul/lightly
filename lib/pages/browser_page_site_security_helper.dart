import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'browser_site_data_manager.dart';
import 'browser_site_security_dialogs.dart';

class BrowserPageSiteSecurityHelper {
  const BrowserPageSiteSecurityHelper();

  Future<void> showSiteSecurityDialog({
    required BuildContext context,
    required String currentUrl,
    required bool isSecure,
    required BrowserSiteDataManager siteDataManager,
    required Future<void> Function(Uri currentUri) onClearSiteData,
  }) async {
    final currentUri = Uri.tryParse(currentUrl);
    final securityState = siteDataManager.buildSecurityState(
      currentUri: currentUri,
      isSecure: isSecure,
    );

    await showBrowserSiteSecurityDialog(
      context: context,
      state: securityState,
      onClearSiteData: () async {
        if (currentUri != null) {
          await onClearSiteData(currentUri);
        }
      },
    );
  }

  Future<String?> clearCurrentSiteData({
    required BuildContext context,
    required Uri currentUri,
    required BrowserSiteDataManager siteDataManager,
    required InAppWebViewController? controller,
  }) async {
    final confirmed = await showBrowserSiteDataClearConfirmation(
      context: context,
      currentUri: currentUri,
    );
    if (!confirmed) {
      return null;
    }

    return siteDataManager.clearCurrentSiteData(
      currentUri: currentUri,
      controller: controller,
    );
  }
}
