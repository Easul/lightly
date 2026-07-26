import '../browser/data/app_database_adapter.dart';
import '../browser/local_http_file_server_service.dart';
import '../browser/services/proxy_service_local_endpoint_adapter.dart';
import '../core/logging/runtime_logger.dart';
import '../core/network/local_proxy_endpoint_provider.dart';
import '../core/storage/app_database_provider.dart';
import '../core/storage/shared_downloads_access.dart';
import '../features/local_sharing/simple_file_manager/simple_file_manager_service.dart';
import '../features/local_sharing/clipboard/clipboard_http_server_service.dart';
import '../services/app_log_service.dart';
import '../services/app_lifecycle_manager.dart';
import '../services/shared_downloads_directory_service.dart';
import 'app_runtime_coordinator.dart';

/// Explicit composition of application-global services.
///
/// Phase 1 composition point: production still uses the existing service
/// implementations, while cross-feature capabilities are exposed as ports so
/// consumers and tests do not depend on those concrete implementations.
class AppServices {
  const AppServices({
    required this.logService,
    required this.lifecycleManager,
    required this.simpleFileManager,
    required this.localProxyEndpoint,
    required this.appDatabase,
    required this.sharedDownloadsAccess,
    required this.runtimeCoordinator,
  });

  /// Wires the current production singletons. Tests may call the default
  /// constructor with fakes instead.
  factory AppServices.production() {
    final logService = AppLogService.instance;
    ClipboardHttpServerService(runtimeLogger: logService);
    LocalHttpFileServerService(runtimeLogger: logService);
    return AppServices(
      logService: logService,
      lifecycleManager: AppLifecycleManager(),
      simpleFileManager: SimpleFileManagerService(runtimeLogger: logService),
      localProxyEndpoint: ProxyServiceLocalEndpointAdapter(),
      appDatabase: AppDatabaseAdapter(),
      sharedDownloadsAccess: SharedDownloadsDirectoryService(),
      runtimeCoordinator: AppRuntimeCoordinator.instance,
    );
  }

  final RuntimeLogger logService;
  final AppLifecycleManager lifecycleManager;
  final SimpleFileManagerService simpleFileManager;

  /// Cross-feature port giving the current local SOCKS5 port. Injected into
  /// features (e.g. Telegram) so they do not depend on the proxy implementation.
  final LocalProxyEndpointProvider localProxyEndpoint;

  /// Cross-feature port giving the shared app database handle. Injected into
  /// features (e.g. AI history) so they do not depend on the browser database.
  final AppDatabaseProvider appDatabase;

  /// Shared permission and fallback policy for user-visible file exports.
  final SharedDownloadsAccess sharedDownloadsAccess;
  final AppRuntimeCoordinator runtimeCoordinator;
}
