import 'package:flutter/material.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/routes/chat/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/routes/chat/events/utils/message_language_correction.dart';
import 'package:fluffychat/routes/settings/settings_learning/p_language_dropdown.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Lets the reader say what language a message is actually in, when the
/// detector read it wrong and the learning tools were disabled as a result.
/// Pops true once the correction is sent.
class MessageLanguageDialog extends StatefulWidget {
  final PangeaMessageEvent messageEvent;

  const MessageLanguageDialog({super.key, required this.messageEvent});

  @override
  MessageLanguageDialogState createState() => MessageLanguageDialogState();
}

class MessageLanguageDialogState extends State<MessageLanguageDialog> {
  LanguageModel? _selectedLanguage;

  bool _loading = false;
  Object? _error;

  /// The dropdown asserts its value is one of its items, so an assigned
  /// language the learner could never have picked (not an L2 option) opens the
  /// dialog empty rather than crashing it.
  List<LanguageModel> get _languages =>
      MatrixState.pangeaController.pLanguageStore.targetOptions;

  @override
  void initState() {
    super.initState();
    final assigned = MessageLanguageCorrection.assignedLanguage(
      widget.messageEvent,
    );
    _selectedLanguage =
        _languages.any((language) => language.langCode == assigned?.langCode)
        ? assigned
        : null;
  }

  void _setLanguage(LanguageModel language) => setState(() {
    _selectedLanguage = language;
    _error = null;
  });

  Future<void> _submit() async {
    final language = _selectedLanguage;
    if (language == null) return;

    try {
      setState(() {
        _loading = true;
        _error = null;
      });

      await MessageLanguageCorrection.apply(widget.messageEvent, language);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e, s) {
      _error = e;
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {
          'eventId': widget.messageEvent.eventId,
          'selected_language': language.langCode,
        },
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      backgroundColor: theme.colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.0)),
      child: Container(
        width: 325.0,
        padding: const EdgeInsets.all(12.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              L10n.of(context).messageLanguage,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24.0),
            PLanguageDropdown(
              onChange: _setLanguage,
              initialLanguage: _selectedLanguage,
              languages: _languages,
              isL2List: true,
              decorationText: L10n.of(context).messageLanguage,
            ),
            const SizedBox(height: 24.0),
            AnimatedSize(
              duration: FluffyThemes.animationDuration,
              child: _error != null
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: 4.0),
                      child: Text(
                        _error!.toLocalizedString(context),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            ElevatedButton(
              onPressed: _selectedLanguage != null && !_loading
                  ? _submit
                  : null,
              child: SizedBox(
                height: 24.0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _loading
                        ? const Expanded(child: LinearProgressIndicator())
                        : Text(L10n.of(context).saveChanges),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
