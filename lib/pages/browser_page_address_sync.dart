import 'package:flutter/widgets.dart';

import '../browser/services/browser_tab_coordinator.dart';

class BrowserPageAddressSync {
  const BrowserPageAddressSync();

  void syncForCurrentTab({
    required BrowserTabCoordinator tabCoordinator,
    required TextEditingController addressController,
  }) {
    final nextText = tabCoordinator.addressBarTextForCurrentTab();
    if (addressController.text == nextText) {
      return;
    }
    addressController.text = nextText;
  }
}
