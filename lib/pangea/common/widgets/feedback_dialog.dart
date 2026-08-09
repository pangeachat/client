import 'package:flutter/material.dart';

import 'package:fluffychat/features/bot/widgets/bot_face_svg.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/dialog_wrapper.dart';

class FeedbackDialog extends StatefulWidget {
  final String title;
  final Function(String) onSubmit;

  final Widget? extraContent;

  const FeedbackDialog({
    super.key,
    required this.title,
    required this.onSubmit,
    this.extraContent,
  });

  @override
  State<FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<FeedbackDialog> {
  final TextEditingController _feedbackController = TextEditingController();

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(
      spacing: 20.0,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Center(
          child: BotFace(width: 50.0, expression: BotExpression.addled),
        ),
        Text(L10n.of(context).feedbackDialogDesc, textAlign: TextAlign.center),
        if (widget.extraContent != null) widget.extraContent!,
        TextFormField(
          controller: _feedbackController,
          decoration: InputDecoration(hintText: L10n.of(context).feedbackHint),
          keyboardType: TextInputType.multiline,
          onFieldSubmitted: _feedbackController.text.isNotEmpty
              ? (value) => widget.onSubmit(value)
              : null,
          minLines: 1,
          maxLines: 5,
          onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
        ),
      ],
    );

    return DialogWrapper(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      maxWidth: 325.0,
      maxHeight: 600.0,
      child: Column(
        spacing: 20.0,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                tooltip: L10n.of(context).close,
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 40.0),
                  alignment: Alignment.center,
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              const SizedBox(
                width: 40.0,
                height: 40.0,
                child: Center(child: Icon(Icons.flag_outlined)),
              ),
            ],
          ),
          Flexible(child: SingleChildScrollView(child: content)),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _feedbackController,
            builder: (context, value, _) {
              final isNotEmpty = value.text.isNotEmpty;
              return ElevatedButton(
                onPressed: isNotEmpty
                    ? () => widget.onSubmit(value.text)
                    : null,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [Text(L10n.of(context).feedbackButton)],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
