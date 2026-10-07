import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_text_input_dialog.dart';

class MarkdownContextMenu extends StatelessWidget {
  final EditableTextState editableTextState;
  final TextEditingController controller;

  const MarkdownContextMenu({
    super.key,
    required this.editableTextState,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final markdownItems = _markdownItems(context);
    // iOS's own menu pastes without the "Allow Paste" prompt that a
    // Flutter-drawn Paste triggers (#9381).
    if (SystemContextMenu.isSupportedByField(editableTextState)) {
      return SystemContextMenu.editableText(
        editableTextState: editableTextState,
        items: [
          ...SystemContextMenu.getDefaultItems(editableTextState),
          for (final item in markdownItems)
            IOSSystemContextMenuItemCustom(
              title: item.label!,
              onPressed: item.onPressed!,
            ),
        ],
      );
    }
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: [
        ...editableTextState.contextMenuButtonItems,
        ...markdownItems,
      ],
    );
  }

  List<ContextMenuButtonItem> _markdownItems(BuildContext context) {
    final value = editableTextState.textEditingValue;
    if (value.selection.textInside(value.text).isEmpty) return [];

    final l10n = L10n.of(context);
    return [
      ContextMenuButtonItem(
        label: l10n.link,
        onPressed: () => _addLink(context),
      ),
      ContextMenuButtonItem(label: l10n.checkList, onPressed: _addCheckList),
      ContextMenuButtonItem(
        label: l10n.boldText,
        onPressed: () => _wrapSelection('**'),
      ),
      ContextMenuButtonItem(
        label: l10n.italicText,
        onPressed: () => _wrapSelection('*'),
      ),
      ContextMenuButtonItem(
        label: l10n.strikeThrough,
        onPressed: () => _wrapSelection('~~'),
      ),
    ];
  }

  Future<void> _addLink(BuildContext context) async {
    final l10n = L10n.of(context);
    final selection = controller.selection;
    final urlString = await showTextInputDialog(
      context: context,
      title: l10n.addLink,
      okLabel: l10n.ok,
      cancelLabel: l10n.cancel,
      validator: (text) {
        if (text.isEmpty) {
          return l10n.pleaseFillOut;
        }
        try {
          text.startsWith('http') ? Uri.parse(text) : Uri.https(text);
        } catch (_) {
          return l10n.invalidUrl;
        }
        return null;
      },
      hintText: 'www...',
      keyboardType: TextInputType.url,
    );
    if (urlString == null) return;
    final url = urlString.startsWith('http')
        ? Uri.parse(urlString)
        : Uri.https(urlString);
    _replace(selection, '[${selection.textInside(controller.text)}]($url)');
  }

  void _addCheckList() {
    final text = controller.text;
    final selection = controller.selection;

    var start = selection.textBefore(text).lastIndexOf('\n');
    if (start == -1) start = 0;
    final fullLineSelection = TextSelection(
      baseOffset: start,
      extentOffset: selection.end,
    );

    const checkBox = '- [ ]';
    final checkedLines = fullLineSelection
        .textInside(text)
        .split('\n')
        .map(
          (line) => line.startsWith(checkBox) || line.isEmpty
              ? line
              : '$checkBox $line',
        )
        .join('\n');
    _replace(fullLineSelection, checkedLines);
  }

  void _wrapSelection(String marker) {
    final selection = controller.selection;
    _replace(
      selection,
      '$marker${selection.textInside(controller.text)}$marker',
    );
  }

  void _replace(TextSelection selection, String replacement) {
    controller.text = controller.text.replaceRange(
      selection.start,
      selection.end,
      replacement,
    );
    ContextMenuController.removeAny();
  }
}
