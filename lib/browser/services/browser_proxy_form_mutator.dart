import '../browser_settings.dart';
import 'browser_settings_form_controller.dart';

class BrowserProxyFormMutator {
  const BrowserProxyFormMutator();

  void changeProtocol(
    BrowserSettingsFormController formController,
    String protocol,
  ) {
    formController.selectedProtocol = protocol;
    if (!formController.showsTransportFields) {
      formController.proxyPacketEncoding = '';
      formController.proxyTransportPathController.clear();
    }
    if (!formController.showsTransportFields &&
        !formController.showsHysteria2ObfsFields) {
      formController.selectedTransportType = '';
      formController.proxyTransportHostController.clear();
    }
    if (formController.showsTransportFields) {
      formController.proxyTransportHostController.clear();
    }
    if (formController.showsHysteria2ObfsFields) {
      formController.proxyTransportPathController.clear();
      formController.proxyPacketEncoding = '';
    }
    if (protocol == BrowserProxyProtocol.vless ||
        protocol == BrowserProxyProtocol.hysteria2) {
      formController.proxyTlsEnabled = true;
      return;
    }
    formController.proxyTlsEnabled = false;
    formController.proxyTlsInsecure = false;
    formController.proxyServerNameController.clear();
  }

  void setTlsEnabled(
    BrowserSettingsFormController formController,
    bool enabled,
  ) {
    formController.proxyTlsEnabled = enabled;
    if (!enabled) {
      formController.proxyTlsInsecure = false;
    }
  }

  void setTransportType(
    BrowserSettingsFormController formController,
    String transportType,
  ) {
    formController.selectedTransportType = transportType;
  }

  void setPacketEncoding(
    BrowserSettingsFormController formController,
    String packetEncoding,
  ) {
    formController.proxyPacketEncoding = packetEncoding;
  }

  void setTlsInsecure(
    BrowserSettingsFormController formController,
    bool enabled,
  ) {
    formController.proxyTlsInsecure = enabled;
  }
}
