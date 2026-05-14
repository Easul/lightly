import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class BrowserAuthDialogService {
  const BrowserAuthDialogService._();

  static Future<HttpAuthResponse?> showAuthDialog(
    BuildContext context,
    URLAuthenticationChallenge challenge,
  ) async {
    final proposedCredential = challenge is HttpAuthenticationChallenge
        ? challenge.proposedCredential
        : null;
    final protectionSpace = challenge.protectionSpace;
    final usernameController = TextEditingController(
      text: proposedCredential?.username ?? '',
    );
    final passwordController = TextEditingController();
    var rememberCredentials = false;

    final response = await showDialog<HttpAuthResponse>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('需要身份验证'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${protectionSpace.host}:${protectionSpace.port}'),
                  if ((protectionSpace.realm ?? '').isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      protectionSpace.realm!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: usernameController,
                    decoration: const InputDecoration(labelText: '用户名'),
                    autofocus: usernameController.text.isEmpty,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passwordController,
                    decoration: const InputDecoration(labelText: '密码'),
                    obscureText: true,
                    autofocus: usernameController.text.isNotEmpty,
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    value: rememberCredentials,
                    onChanged: (value) {
                      setDialogState(() {
                        rememberCredentials = value ?? false;
                      });
                    },
                    contentPadding: EdgeInsets.zero,
                    title: const Text('记住凭据'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop(
                      HttpAuthResponse(action: HttpAuthResponseAction.CANCEL),
                    );
                  },
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop(
                      HttpAuthResponse(
                        username: usernameController.text.trim(),
                        password: passwordController.text,
                        permanentPersistence: rememberCredentials,
                        action: HttpAuthResponseAction.PROCEED,
                      ),
                    );
                  },
                  child: const Text('登录'),
                ),
              ],
            );
          },
        );
      },
    );

    usernameController.dispose();
    passwordController.dispose();
    return response ?? HttpAuthResponse(action: HttpAuthResponseAction.CANCEL);
  }
}
