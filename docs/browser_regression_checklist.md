# Browser 回归验证清单

本清单用于 Browser / WebView 相关重构、修复、发布前的人工验证。自动测试通过不代表这些路径已经验证完成。

## 自动验证

```bash
flutter analyze lib/pages/browser_page.dart
flutter test test/browser/
```

如果触碰代理 / VLESS / WebView 热路径，按 `AGENTS.md` 追加对应 proxy / VLESS 测试与 release build。

## 基础浏览

- [ ] 启动应用进入浏览器首页。
- [ ] 输入普通网址并完成加载，地址栏显示最终 URL。
- [ ] 输入搜索词，确认跳转到搜索页。
- [ ] 页面加载进度条显示平滑，加载完成后隐藏。
- [ ] 刷新 / 停止加载按钮状态正确。

## 标签页

- [ ] 新建标签页。
- [ ] 切换已有标签页，地址栏、标题、收藏状态同步。
- [ ] 关闭当前标签页，active tab 落到预期标签。
- [ ] 关闭所有标签页后回到默认首页。
- [ ] 快速切换多个标签页无闪退、无明显卡顿。

## WebView callback 行为

- [ ] 页面标题变化后 tab title 更新。
- [ ] 页面历史变化后前进 / 后退按钮状态正确。
- [ ] 滚动页面后返回该 tab，滚动位置按现有规则恢复。
- [ ] 加载错误页时错误状态显示正常。
- [ ] `onProgressChanged` 不导致全页高频重建或底栏图标闪烁。

## 弹窗与认证

- [ ] 普通空 URL 图片弹窗仍被抑制。
- [ ] 登录 / OAuth / Telegram 类授权弹窗可打开。
- [ ] HTTP Basic Auth 页面弹出用户名/密码对话框。
- [ ] Popup WebView 中的 HTTP Auth 同样可输入并继续。

## 查找与地址栏

- [ ] 从首页和普通网页都能打开 find-in-page。
- [ ] 输入查找词后结果计数与上一项 / 下一项正常。
- [ ] 地址栏清空、编辑、提交不触发 BrowserPage 全量频繁重建。

## 站点数据与 Cookie

- [ ] 锁图标打开当前站点数据对话框。
- [ ] 清除该网站数据后 toast 文案说明“不含全局缓存”。
- [ ] 清除历史不会清掉 cookie-origin index 中仍有 Cookie 的站点。
- [ ] 备份导出包含已访问且有 Cookie 的真实来源。

## 代理与兼容站点

- [ ] 未启用代理时普通页面直连正常。
- [ ] 启用代理后普通页面可加载。
- [ ] 内置 bypass 域名仍直连。
- [ ] Cloudflare challenge / 登录类站点不因弹窗或 bypass 行为回退。
- [ ] X / YouTube 使用移动布局，无底部导航异常空白。

## 性能烟测

- [ ] 加载动态页面时打开/关闭抽屉动画平滑。
- [ ] 打开/关闭 tab switcher sheet 动画平滑。
- [ ] 长页面滚动无明显掉帧。
- [ ] 视频检测页面无持续高 CPU / 高频日志。
