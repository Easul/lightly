import '../browser/data/browser_database_app_provider.dart';
import '../browser/services/proxy_service_local_endpoint_adapter.dart';
import '../core/network/local_proxy_endpoint_provider.dart';
import '../core/storage/app_database_provider.dart';
import '../services/app_log_service.dart';
import '../services/app_lifecycle_manager.dart';
import '../services/simple_file_manager_service.dart';

/// Explicit composition of application-global services.
///
/// Phase 1 skeleton: this only *centralizes* the singletons that `main.dart`
/// previously reached for directly. It intentionally does NOT invert any
/// dependency or change service behavior yet — each field still resolves to
/// the existing singleton. Later steps replace individual fields with injected
/// ports (e.g. [AppLogService] behind a `RuntimeLogger` port) without touching
/// the bootstrap call site.
class AppServices {
  const AppServices({
    required this.logService,
    required this.lifecycleManager,
    required this.simpleFileManager,
    required this.localProxyEndpoint,
    required this.appDatabase,
  });

  /// Wires the current production singletons. Tests may call the default
  /// constructor with fakes instead.
  factory AppServices.production() {
    return AppServices(
      logService: AppLogService.instance,
      lifecycleManager: AppLifecycleManager(),
      simpleFileManager: SimpleFileManagerService(),
      localProxyEndpoint: ProxyServiceLocalEndpointAdapter(),
      appDatabase: BrowserDatabaseAppProvider(),
    );
  }

  final AppLogService logService;
  final AppLifecycleManager lifecycleManager;
  final SimpleFileManagerService simpleFileManager;

  /// Cross-feature port giving the current local SOCKS5 port. Injected into
  /// features (e.g. Telegram) so they do not depend on the proxy implementation.
  final LocalProxyEndpointProvider localProxyEndpoint;

  /// Cross-feature port giving the shared app database handle. Injected into
  /// features (e.g. AI history) so they do not depend on the browser database.
  final AppDatabaseProvider appDatabase;
}
