import 'package:flutter/material.dart';

import '../services/browser_find_controller.dart';

Future<void> showBrowserFindInPageSheet({
  required BuildContext context,
  required BrowserFindController findController,
}) async {
  final searchController = TextEditingController();

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: ValueListenableBuilder<int>(
              valueListenable: findController.revision,
              builder: (context, _, __) {
                final hasMatches = findController.matchCount > 0;
                final currentLabel = hasMatches
                    ? findController.currentMatch + 1
                    : 0;
                return Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: searchController,
                        autofocus: true,
                        textInputAction: TextInputAction.search,
                        onChanged: (_) => findController.notifyQueryChanged(),
                        decoration: InputDecoration(
                          hintText: '页面内搜索',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    searchController.clear();
                                    findController.clearMatches();
                                    findController.resetResults();
                                  },
                                )
                              : null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        onSubmitted: (value) async {
                          if (value.trim().isEmpty) {
                            return;
                          }
                          await findController.findAll(value);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '$currentLabel / ${findController.matchCount}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_up),
                      onPressed: hasMatches
                          ? () async {
                              await findController.findNext(forward: false);
                            }
                          : null,
                    ),
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_down),
                      onPressed: hasMatches
                          ? () async {
                              await findController.findNext(forward: true);
                            }
                          : null,
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        findController.clearMatches();
                        Navigator.of(context).pop();
                      },
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
    },
  );

  searchController.dispose();
  findController.clearMatches();
  findController.resetResults();
}
