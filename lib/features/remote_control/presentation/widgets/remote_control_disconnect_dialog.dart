import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../theme/app_theme.dart';
import '../../domain/remote_control_runtime.dart';

Future<void> showRemoteDisconnectDialog({
  required BuildContext context,
  required GlobalKey<NavigatorState> navigatorKey,
  required RemoteControlOverlayRuntime overlayRuntime,
  required String message,
}) async {
  final dialogContext = navigatorKey.currentContext ?? context;
  try {
    final didShowGlobalOverlay = await overlayRuntime.showDisconnectOverlay(
      message,
    );
    if (didShowGlobalOverlay == true) {
      return;
    }
  } on MissingPluginException {
    // Fall back to the in-app dialog on platforms without the native overlay.
  } catch (_) {
    // Fall back to the in-app dialog if the accessibility overlay is unavailable.
  }

  if (!dialogContext.mounted) {
    return;
  }
  await showGeneralDialog<void>(
    context: dialogContext,
    useRootNavigator: true,
    barrierDismissible: false,
    barrierColor: const Color(0xFF56605A).withValues(alpha: 0.24),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, animation, secondaryAnimation) {
      return RemoteDisconnectDialog(message: message);
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class RemoteDisconnectDialog extends StatelessWidget {
  const RemoteDisconnectDialog({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: (MediaQuery.sizeOf(context).width - 48).clamp(260.0, 360.0),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppColors.divider),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF68706B).withValues(alpha: 0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.dangerContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.link_off_rounded,
                        color: AppColors.danger,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        '对方已断开',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.scaffoldBackground,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Text(
                    message,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                      height: 1.45,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: () =>
                      Navigator.of(context, rootNavigator: true).pop(),
                  child: const Text('关闭'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
