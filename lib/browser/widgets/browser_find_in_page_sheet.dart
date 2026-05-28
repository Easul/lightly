import 'dart:async';

import 'package:flutter/material.dart';

import '../services/browser_find_controller.dart';

Future<void> showBrowserFindInPageSheet({
  required BuildContext context,
  required BrowserFindController findController,
}) async {
  final searchController = TextEditingController();
  Timer? searchDebounce;

  Future<void> runSearch(String value) async {
    final keyword = value.trim();
    if (keyword.isEmpty) {
      findController.clearMatches();
      findController.resetResults();
      return;
    }
    await findController.findAll(keyword);
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setModalState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: ValueListenableBuilder<int>(
                valueListenable: findController.revision,
                builder: (context, revision, child) {
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
                          onChanged: (value) {
                            setModalState(() {});
                            findController.notifyQueryChanged();
                            searchDebounce?.cancel();
                            searchDebounce = Timer(
                              const Duration(milliseconds: 250),
                              () => unawaited(runSearch(value)),
                            );
                          },
                          decoration: InputDecoration(
                            hintText: '页面内搜索',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      searchController.clear();
                                      searchDebounce?.cancel();
                                      unawaited(runSearch(''));
                                      setModalState(() {});
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
                            searchDebounce?.cancel();
                            await runSearch(value);
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
        ),
      );
    },
  );

  searchDebounce?.cancel();
  searchController.dispose();
  findController.clearMatches();
  findController.resetResults();
}
