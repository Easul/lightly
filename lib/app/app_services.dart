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
  });

  /// Wires the current production singletons. Tests may call the default
  /// constructor with fakes instead.
  factory AppServices.production() {
    return AppServices(
      logService: AppLogService.instance,
      lifecycleManager: AppLifecycleManager(),
      simpleFileManager: SimpleFileManagerService(),
    );
  }

  final AppLogService logService;
  final AppLifecycleManager lifecycleManager;
  final SimpleFileManagerService simpleFileManager;
}
