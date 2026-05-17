import '../browser_settings.dart';
import '../models/browser_subscription_node.dart';
import 'browser_subscription_service.dart';

class BrowserNodeLinkParserException implements Exception {
  const BrowserNodeLinkParserException(this.message);

  final String message;

  @override
  String toString() => message;
}

class BrowserNodeLinkParseResult {
  const BrowserNodeLinkParseResult({
    required this.node,
    required this.settings,
  });

  final BrowserSubscriptionNode node;
  final BrowserSettings settings;
}

class BrowserNodeLinkParser {
  BrowserNodeLinkParser({BrowserSubscriptionService? subscriptionService})
    : _subscriptionService =
          subscriptionService ?? BrowserSubscriptionService();

  final BrowserSubscriptionService _subscriptionService;

  BrowserNodeLinkParseResult parseNodeLink(
    String link, {
    required BrowserSettings currentSettings,
  }) {
    final trimmedLink = link.trim();
    if (trimmedLink.isEmpty) {
      throw const BrowserNodeLinkParserException('请输入节点链接');
    }

    final node = _subscriptionService.parseSingleNode(trimmedLink);
    if (node == null) {
      throw const BrowserNodeLinkParserException(
        '无法解析该链接，仅支持 vless://、hysteria2:// 和 http:// 格式',
      );
    }

    return BrowserNodeLinkParseResult(
      node: node,
      settings: _subscriptionService.convertNodeToSettings(
        node,
        currentSettings: currentSettings,
      ),
    );
  }

  BrowserSettings resolveSettingsForSpeedTest(
    String link, {
    required BrowserSettings currentSettings,
  }) {
    final trimmedLink = link.trim();
    if (trimmedLink.isEmpty) {
      return currentSettings;
    }

    return parseNodeLink(
      trimmedLink,
      currentSettings: currentSettings,
    ).settings;
  }
}
