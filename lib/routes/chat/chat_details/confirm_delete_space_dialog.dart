import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/adaptive_dialog_action.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/dialog_text_field.dart';

/// Deleting a course destroys the space, its chats and everyone's messages, so
/// the admin has to type the course code back before the delete action unlocks.
/// A course that never had a code generated confirms on its name instead.
class ConfirmDeleteSpaceDialog extends StatefulWidget {
  final String? joinCode;
  final String displayname;
  final bool hasSpaceChildren;

  const ConfirmDeleteSpaceDialog({
    super.key,
    required this.joinCode,
    required this.displayname,
    required this.hasSpaceChildren,
  });

  String get confirmationValue => joinCode ?? displayname;

  @override
  State<ConfirmDeleteSpaceDialog> createState() =>
      ConfirmDeleteSpaceDialogState();
}

class ConfirmDeleteSpaceDialogState extends State<ConfirmDeleteSpaceDialog> {
  final TextEditingController _controller = TextEditingController();
  final ValueNotifier<bool> _isConfirmed = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onInputChanged);
  }

  @override
  void dispose() {
    _controller.dispose();
    _isConfirmed.dispose();
    super.dispose();
  }

  void _onInputChanged() {
    _isConfirmed.value =
        _controller.text.trim().toLowerCase() ==
        widget.confirmationValue.trim().toLowerCase();
  }

  void _confirm() {
    if (!_isConfirmed.value) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final joinCode = widget.joinCode;

    return AlertDialog.adaptive(
      // The description, the prompt and the field together outgrow a short
      // screen — more so with the keyboard up.
      scrollable: true,
      title: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 256),
        child: Text(l10n.areYouSure),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 256),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 16.0,
          children: [
            Text(
              widget.hasSpaceChildren
                  ? l10n.deleteSpaceDesc
                  : l10n.deleteEmptySpaceDesc,
            ),
            Text(
              joinCode != null
                  ? l10n.typeCourseCodeToConfirm(joinCode)
                  : l10n.typeCourseNameToConfirm(widget.displayname),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            DialogTextField(
              controller: _controller,
              labelText: joinCode != null
                  ? l10n.courseCodeHint
                  : l10n.courseNameHint,
              onSubmitted: (_) => _confirm(),
            ),
          ],
        ),
      ),
      actions: [
        AdaptiveDialogAction(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: _isConfirmed,
          builder: (context, isConfirmed, _) => AdaptiveDialogAction(
            onPressed: isConfirmed ? _confirm : null,
            child: Text(
              l10n.delete,
              style: TextStyle(
                color: isConfirmed ? theme.colorScheme.error : null,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
