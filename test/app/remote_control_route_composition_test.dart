import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lightly/app/remote_control_page_coordinator.dart';
import 'package:lightly/app/routes.dart';
import 'package:lightly/features/remote_control/infrastructure/remote_control_platform_gateway.dart';
import 'package:lightly/features/remote_control/presentation/pages/remote_control_page.dart';
import 'package:lightly/services/app_log_service.dart';
import 'package:lightly/services/app_toast.dart';
import 'package:lightly/services/remote_control_service.dart';

void main() {
  testWidgets('remote-control route composes the existing session owner', (
    tester,
  ) async {
    RemoteControlPage? page;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            page =
                buildAppRoutes()['/remote-control']!(context)
                    as RemoteControlPage;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(page, isNotNull);
    expect(page!.service, same(RemoteControlService()));
    expect(page!.runtimeCoordinator, isA<RemoteControlPageCoordinator>());
    expect(page!.platformRuntime, same(RemoteControlPlatformGateway.instance));
    expect(page!.runtimeLogger, same(AppLogService.instance));
    expect(page!.navigatorKey, same(AppToast.navigatorKey));
  });
}
