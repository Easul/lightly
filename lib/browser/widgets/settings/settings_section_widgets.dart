import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../widgets/shared/primary_button.dart';
import '../../../widgets/shared/setting_tile.dart';

class SettingsSectionHeader extends StatelessWidget {
  const SettingsSectionHeader({
    super.key,
    required this.title,
    required this.icon,
  });

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 18, color: colorScheme.primary),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
}

typedef SettingsTile = SettingTile;

class SettingsSectionPage extends StatelessWidget {
  const SettingsSectionPage({
    super.key,
    required this.title,
    required this.icon,
    required this.revisionListenable,
    required this.isSavingBuilder,
    required this.buildChildren,
    required this.onSave,
  });

  final String title;
  final IconData icon;
  final ValueListenable<int> revisionListenable;
  final bool Function() isSavingBuilder;
  final List<Widget> Function(BuildContext context) buildChildren;
  final Future<void> Function() onSave;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 10),
            Text(title),
          ],
        ),
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: revisionListenable,
        builder: (context, _, __) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: buildChildren(context),
          );
        },
      ),
      bottomNavigationBar: ValueListenableBuilder<int>(
        valueListenable: revisionListenable,
        builder: (context, _, __) {
          final isSaving = isSavingBuilder();
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: PrimaryButton.outlined(
                      onPressed: isSaving
                          ? null
                          : () => Navigator.of(context).pop(),
                      label: '返回',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: PrimaryButton(
                      onPressed: isSaving ? null : onSave,
                      label: isSaving ? '保存中...' : '保存',
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class SettingsHomeSectionsCard extends StatelessWidget {
  const SettingsHomeSectionsCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SettingsCard(children: children);
  }
}

class SettingsHomeBottomActions extends StatelessWidget {
  const SettingsHomeBottomActions({
    super.key,
    required this.isSaving,
    required this.onCancel,
    required this.onSave,
  });

  final bool isSaving;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: isSaving ? null : onCancel,
                child: const Text('取消'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: isSaving ? null : onSave,
                child: Text(isSaving ? '保存中...' : '保存'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
