import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/services/app_version_info.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  group('AppVersionInfo', () {
    AppVersionInfo infoFor({String version = '', String buildNumber = '1'}) {
      return AppVersionInfo(
        packageInfo: PackageInfo(
          appName: '若轻',
          packageName: 'lightly.tool',
          version: version,
          buildNumber: buildNumber,
        ),
      );
    }

    test('发布构建（tag+commit）原样展示', () {
      final info = infoFor(version: '1.0.8+a39a9dc', buildNumber: '5064');
      expect(info.displayVersion, 'v1.0.8+a39a9dc');
      expect(info.semanticVersion, '1.0.8');
      expect(info.commitHash, 'a39a9dc');
    });

    test('本地开发构建（无 commit）补全 v 前缀', () {
      final info = infoFor(version: '1.0.1', buildNumber: '2');
      expect(info.displayVersion, 'v1.0.1');
      expect(info.semanticVersion, '1.0.1');
      expect(info.commitHash, isEmpty);
    });

    test('版本号已带 v 前缀时不重复补全', () {
      final info = infoFor(version: 'v1.0.8+a39a9dc', buildNumber: '5064');
      expect(info.displayVersion, 'v1.0.8+a39a9dc');
      expect(info.semanticVersion, '1.0.8');
      expect(info.commitHash, 'a39a9dc');
    });

    test('空版本号退化为 buildNumber', () {
      final info = infoFor(version: '', buildNumber: '5064');
      expect(info.displayVersion, 'v5064');
    });

    test('以 + 结尾时不暴露空 commit', () {
      final info = infoFor(version: '1.0.8+', buildNumber: '5064');
      expect(info.displayVersion, 'v1.0.8+');
      expect(info.commitHash, isEmpty);
    });
  });
}
