import 'dart:async';

import 'package:fluffychat/pangea/controllers/language_list_controller.dart';
import 'package:fluffychat/pangea/controllers/pangea_controller.dart';
import 'package:fluffychat/pangea/models/language_model.dart';
import 'package:fluffychat/pangea/pages/sign_up/user_settings_view.dart';
import 'package:fluffychat/pangea/utils/error_handler.dart';
import 'package:fluffychat/utils/file_selector.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/l10n.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

class UserSettingsPage extends StatefulWidget {
  const UserSettingsPage({super.key});

  @override
  UserSettingsState createState() => UserSettingsState();
}

class UserSettingsState extends State<UserSettingsPage> {
  PangeaController get _pangeaController => MatrixState.pangeaController;

  LanguageModel? selectedTargetLanguage;

  String? selectedLanguageError;
  String? profileCreationError;

  bool loading = false;

  Uint8List? avatar;
  String? _selectedFilePath;

  List<String> avatarPaths = const [
    "assets/pangea/Avatar_1.png",
    "assets/pangea/Avatar_2.png",
    "assets/pangea/Avatar_3.png",
    "assets/pangea/Avatar_4.png",
    "assets/pangea/Avatar_5.png",
  ];
  String? selectedAvatarPath;

  LanguageModel? get _systemLanguage {
    final systemLangCode =
        _pangeaController.languageController.systemLanguage?.langCode;
    return systemLangCode == null
        ? null
        : PangeaLanguage.byLangCode(systemLangCode);
  }

  @override
  void initState() {
    super.initState();
    selectedTargetLanguage = _pangeaController.languageController.userL2;
    selectedAvatarPath = avatarPaths.first;
  }

  void setSelectedTargetLanguage(LanguageModel? language) {
    setState(() {
      selectedTargetLanguage = language;
      selectedLanguageError = null;
    });
  }

  void setSelectedAvatarPath(int index) {
    if (index < 0 || index >= avatarPaths.length) return;
    setState(() {
      avatar = null;
      selectedAvatarPath = avatarPaths[index];
    });
  }

  int get selectedAvatarIndex {
    if (selectedAvatarPath == null) return -1;
    return avatarPaths.indexOf(selectedAvatarPath!);
  }

  void uploadAvatar() async {
    final photo = await selectFiles(
      context,
      type: FileSelectorType.images,
      allowMultiple: false,
    );
    final selectedFile = photo.singleOrNull;
    final bytes = await selectedFile?.readAsBytes();
    final path = selectedFile?.path;

    setState(() {
      selectedAvatarPath = null;
      avatar = bytes;
      _selectedFilePath = path;
    });
  }

  Future<void> _setAvatar() async {
    final client = Matrix.of(context).client;
    try {
      MatrixFile? file;
      if (avatar != null && _selectedFilePath != null) {
        file = MatrixFile(
          bytes: avatar!,
          name: _selectedFilePath!,
        );
      } else if (selectedAvatarPath != null) {
        final ByteData byteData = await rootBundle.load(selectedAvatarPath!);
        final Uint8List bytes = byteData.buffer.asUint8List();
        file = MatrixFile(
          bytes: bytes,
          name: selectedAvatarPath!,
        );
      }
      if (file != null) await client.setAvatar(file);
    } catch (err, s) {
      ErrorHandler.logError(e: err, s: s);
    }
  }

  Future<void> createUserInPangea() async {
    setState(() => profileCreationError = null);

    if (selectedTargetLanguage == null) {
      setState(() {
        selectedLanguageError = L10n.of(context).pleaseSelectALanguage;
      });
      return;
    }

    setState(() => loading = true);

    try {
      final updateFuture = [
        _setAvatar(),
        _pangeaController.subscriptionController.reinitialize(),
        _pangeaController.userController.updateProfile(
          (profile) {
            if (_systemLanguage != null) {
              profile.userSettings.sourceLanguage = _systemLanguage!.langCode;
            }
            profile.userSettings.targetLanguage =
                selectedTargetLanguage!.langCode;
            profile.userSettings.createdAt = DateTime.now();
            return profile;
          },
          waitForDataInSync: true,
        ),
      ];
      await Future.wait(updateFuture).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException(L10n.of(context).oopsSomethingWentWrong);
        },
      );
      context.go('/rooms');
    } catch (err) {
      if (err is MatrixException) {
        profileCreationError = err.errorMessage;
      } else {
        profileCreationError = err.toLocalizedString(context);
      }
      if (mounted) setState(() {});
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  List<LanguageModel> get targetOptions =>
      _pangeaController.pLanguageStore.targetOptions;

  @override
  Widget build(BuildContext context) => UserSettingsView(controller: this);
}
