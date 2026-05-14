import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/pages/browser_page_status_helper.dart';

void main() {
  test('BrowserPageStatusHelper returns stable page status strings', () {
    const helper = BrowserPageStatusHelper();

    expect(helper.cleared(), '');
    expect(helper.youtubeResolving(), '正在解析 YouTube 视频');
    expect(helper.blockedPopup(), '网页拦截了当前弹窗/跳转，请确认是否外部打开');
    expect(helper.externalAppContinuing(), '检测到外部应用跳转，正在尝试继续');
  });
}
