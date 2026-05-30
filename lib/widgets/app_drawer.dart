import 'package:flutter/material.dart';

import 'app_drawer_sections.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key, this.onOpenSettings});

  final Future<void> Function()? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final currentRoute = ModalRoute.of(context)?.settings.name;
    final colorScheme = Theme.of(context).colorScheme;

    return Drawer(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(32)),
      ),
      backgroundColor: colorScheme.surface,
      child: Column(
        children: [
          const DrawerBrandHeader(),
          Expanded(
            child: DrawerNavigationList(
              currentRoute: currentRoute,
              onOpenSettings: onOpenSettings,
            ),
          ),
          SafeArea(top: false, child: const DrawerVersionFooter()),
        ],
      ),
    );
  }
}
