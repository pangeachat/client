import 'package:flutter/material.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/languages/language_model.dart';
import 'package:fluffychat/pangea/learning_settings/language_mismatch_popup.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import '../../widgets/matrix.dart';
import 'p_language_dropdown.dart';

class PLanguageDialog extends StatefulWidget {
  final LanguageModel? initialBaseLanguage;
  final LanguageModel? initialTargetLanguage;

  const PLanguageDialog({
    super.key,
    required this.initialBaseLanguage,
    required this.initialTargetLanguage,
  });

  @override
  PLanguageDialogState createState() => PLanguageDialogState();
}

class PLanguageDialogState extends State<PLanguageDialog> {
  LanguageModel? _selectedBaseLanguage;
  LanguageModel? _selectedTargetLanguage;

  bool _loading = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _selectedBaseLanguage = widget.initialBaseLanguage;
    _selectedTargetLanguage = widget.initialTargetLanguage;
  }

  void _setBaseLanguage(LanguageModel lang) => setState(() {
    _selectedBaseLanguage = lang;
    _error = null;
  });

  void _setTargetLanguage(LanguageModel lang) => setState(() {
    _selectedTargetLanguage = lang;
    _error = null;
  });

  Future<void> _setLanguages() async {
    final base = _selectedBaseLanguage;
    final target = _selectedTargetLanguage;

    if (base == null || target == null) {
      throw MissingLanguageException();
    }

    if (base.langCodeShort == target.langCodeShort) {
      throw IdenticalLanguageException();
    }

    await MatrixState.pangeaController.userController.updateProfile(
      (profile) => profile.copyWith(
        userSettings: profile.userSettings.copyWith(
          sourceLanguage: base.langCode,
          targetLanguage: target.langCode,
        ),
      ),
      waitForDataInSync: true,
    );
  }

  Future<void> _submit() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
      });

      await _setLanguages();
      Navigator.of(context).pop();
    } catch (e, s) {
      _error = e;
      ErrorHandler.logError(
        e: e,
        s: s,
        data: {
          'selected_base_language': _selectedBaseLanguage?.langCode,
          'selected_target_language': _selectedTargetLanguage?.langCode,
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
        padding: EdgeInsets.all(12.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              L10n.of(context).updateLanguage,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 24.0),
            Column(
              spacing: 12.0,
              mainAxisSize: MainAxisSize.min,
              children: [
                PLanguageDropdown(
                  onChange: _setBaseLanguage,
                  initialLanguage: _selectedBaseLanguage,
                  languages:
                      MatrixState.pangeaController.pLanguageStore.baseOptions,
                  isL2List: false,
                  decorationText: L10n.of(context).whatIsYourBaseLanguage,
                ),
                PLanguageDropdown(
                  onChange: _setTargetLanguage,
                  initialLanguage: _selectedTargetLanguage,
                  languages:
                      MatrixState.pangeaController.pLanguageStore.targetOptions,
                  isL2List: true,
                  decorationText: L10n.of(context).whatLanguageYouWantToLearn,
                ),
              ],
            ),
            SizedBox(height: 24.0),
            AnimatedSize(
              duration: FluffyThemes.animationDuration,
              child: _error != null
                  ? Padding(
                      padding: EdgeInsets.only(bottom: 4.0),
                      child: Text(
                        _error!.toLocalizedString(context),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    )
                  : SizedBox.shrink(),
            ),
            ElevatedButton(
              onPressed: _error == null && !_loading ? _submit : null,
              child: SizedBox(
                height: 24.0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _loading
                        ? Expanded(child: LinearProgressIndicator())
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
