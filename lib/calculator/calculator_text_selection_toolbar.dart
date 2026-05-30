import 'package:flutter/material.dart';

Widget buildChineseTextSelectionToolbar(
  BuildContext context,
  EditableTextState editableTextState,
) {
  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: editableTextState.contextMenuAnchors,
    buttonItems: <ContextMenuButtonItem>[
      if (editableTextState.copyEnabled)
        ContextMenuButtonItem(
          onPressed: () {
            editableTextState.copySelection(SelectionChangedCause.toolbar);
          },
          label: '复制',
        ),
      if (editableTextState.cutEnabled)
        ContextMenuButtonItem(
          onPressed: () {
            editableTextState.cutSelection(SelectionChangedCause.toolbar);
          },
          label: '剪切',
        ),
      if (editableTextState.pasteEnabled)
        ContextMenuButtonItem(
          onPressed: () {
            editableTextState.pasteText(SelectionChangedCause.toolbar);
          },
          label: '粘贴',
        ),
      if (editableTextState.selectAllEnabled)
        ContextMenuButtonItem(
          onPressed: () {
            editableTextState.selectAll(SelectionChangedCause.toolbar);
          },
          label: '全选',
        ),
    ],
  );
}
