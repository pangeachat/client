import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:matrix/matrix.dart';
import 'package:mime/mime.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/onboarding/onboarding_state_controller.dart';
import 'package:fluffychat/routes/onboarding/onboarding_steps/profile_setup_onboarding_step.dart';
import 'package:fluffychat/utils/file_selector.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/url_image_widget.dart';

class ProfileSetupStepView extends StatefulWidget {
  final ProfileSetupOnboardingStep step;
  final bool loading;
  final bool hasNextStep;
  final VoidCallback forward;

  const ProfileSetupStepView({
    super.key,
    required this.step,
    required this.loading,
    required this.hasNextStep,
    required this.forward,
  });

  @override
  ProfileSetupStepViewState createState() => ProfileSetupStepViewState();
}

class ProfileSetupStepViewState extends State<ProfileSetupStepView> {
  late final ProfileSetupOnboardingStep _step;

  final TextEditingController _displayNameController = TextEditingController();

  final ValueNotifier<AvatarInfo> _avatarNotifier = ValueNotifier(AvatarInfo());

  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _step = widget.step;
    _displayNameController.addListener(_setDisplayName);
    _setDefaultProfileInfo();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _displayNameController.removeListener(_setDisplayName);
    _displayNameController.dispose();
    _avatarNotifier.dispose();
    super.dispose();
  }

  List<Uri> get _avatarOptions =>
      List.generate(5, (index) => Uri.parse(_avatarUrlString(index + 1)));

  String _avatarUrlString(int index) =>
      "${AppConfig.assetsBaseURL}/avatar_$index.png";

  String _avatarDescription(int index) {
    switch (index) {
      case 0:
        return L10n.of(context).dinoAvatarLabel;
      case 1:
        return L10n.of(context).bearAvatarLabel;
      case 2:
        return L10n.of(context).squidAvatarLabel;
      case 3:
        return L10n.of(context).cartoonAvatarLabel;
      case 4:
        return L10n.of(context).robotAvatarLabel;
      default:
        return L10n.of(context).defaultOption;
    }
  }

  void _setDisplayName() {
    _debounce?.cancel();
    _debounce = Timer(Duration(milliseconds: 300), () {
      _step.setDisplayName(_displayNameController.text);
      _debounce?.cancel();
      _debounce = null;
    });
  }

  void _setAvatarUrl(Uri url) {
    _step.setAvatarUrl(url);
    _avatarNotifier.value = AvatarInfo(avatarUrl: url);
  }

  void _setAvatarBytes(Uint8List bytes) {
    _step.setAvatarBytes(bytes);
    _avatarNotifier.value = AvatarInfo(avatarBytes: bytes);
  }

  Future<void> _setDefaultProfileInfo() async {
    final client = Matrix.of(context).client;
    final userID = client.userID!;
    final profile = await client.fetchOwnProfile();

    final avatarInfo = _step.state.avatarInfo;
    final avatarBytes = avatarInfo?.avatarBytes;
    final avatarUrl = avatarInfo?.avatarUrl ?? profile.avatarUrl;

    if (avatarBytes != null) {
      _setAvatarBytes(avatarBytes);
    } else if (avatarUrl != null) {
      _setAvatarUrl(avatarUrl);
    }

    final displayName =
        _step.state.displayName ??
        profile.displayName ??
        userID.localpart ??
        userID;

    _step.setDisplayName(displayName);
    _displayNameController.text = displayName;
  }

  Future<void> _uploadAvatarImage() async {
    final picked = await selectFiles(
      context,
      allowMultiple: false,
      type: FileType.image,
    );

    await showFutureLoadingDialog(
      context: context,
      future: () async {
        final pickedFile = picked.firstOrNull;
        if (pickedFile == null) return;
        final bytes = await pickedFile.readAsBytes();

        final mimeType = lookupMimeType(pickedFile.name, headerBytes: bytes);

        if (!AppConfig.allowedMimeTypes.contains(mimeType)) {
          throw L10n.of(context).invalidInput;
        }

        _setAvatarBytes(bytes);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      spacing: 32.0,
      children: [
        Expanded(
          child: Center(
            child: Semantics(
              label: L10n.of(context).profile,
              container: true,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Semantics(
                      label: L10n.of(context).changeYourAvatar,
                      container: true,
                      child: ValueListenableBuilder(
                        valueListenable: _avatarNotifier,
                        builder: (context, _, _) {
                          final avatarInfo = _step.state.avatarInfo;
                          final avatarBytes = avatarInfo?.avatarBytes;
                          final avatarUrl = avatarInfo?.avatarUrl;

                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                height: 110.0,
                                width: 110.0,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(
                                        100.0,
                                      ),
                                      child: ExcludeSemantics(
                                        child: Container(
                                          width: 100.0,
                                          height: 100.0,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              100.0,
                                            ),
                                            color: theme.disabledColor,
                                          ),
                                          child: avatarUrl != null
                                              ? ImageByUrl(
                                                  width: 100.0,
                                                  imageUrl: avatarUrl,
                                                )
                                              : avatarBytes != null
                                              ? Image.memory(
                                                  avatarBytes,
                                                  fit: BoxFit.cover,
                                                  semanticLabel: L10n.of(
                                                    context,
                                                  ).avatarPreview,
                                                )
                                              : SizedBox(),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      right: 0,
                                      bottom: 0,
                                      child: Semantics(
                                        label: L10n.of(
                                          context,
                                        ).selectImageFromDevice,
                                        container: true,
                                        child: IconButton.filled(
                                          tooltip: L10n.of(
                                            context,
                                          ).changeYourAvatar,
                                          icon: Icon(
                                            Icons.file_upload_outlined,
                                          ),
                                          onPressed: _uploadAvatarImage,
                                          style: IconButton.styleFrom(
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12.0),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(height: 20.0),
                              Row(
                                spacing: 6.0,
                                mainAxisSize: MainAxisSize.min,
                                children: _avatarOptions
                                    .mapIndexed(
                                      (index, avatarUrl) => Semantics(
                                        label: _avatarDescription(index),
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(
                                            100.0,
                                          ),
                                          onTap: () => _setAvatarUrl(avatarUrl),
                                          child: SizedBox(
                                            height: 32.0,
                                            width: 32.0,
                                            child: ImageByUrl(
                                              width: 32.0,
                                              imageUrl: avatarUrl,
                                              borderRadius:
                                                  BorderRadius.circular(100.0),
                                            ),
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    SizedBox(height: 12.0),
                    ExcludeSemantics(
                      child: Text(
                        L10n.of(context).displayName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    SizedBox(height: 8.0),
                    Semantics(
                      label: L10n.of(context).displayName,
                      container: true,
                      child: ValueListenableBuilder(
                        valueListenable: _displayNameController,
                        builder: (context, text, _) => TextField(
                          controller: _displayNameController,
                          maxLength: 50,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        ElevatedButton(
          onPressed: _step.enableGoForward ? widget.forward : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primaryContainer,
            foregroundColor: theme.colorScheme.onPrimaryContainer,
            minimumSize: const Size.fromHeight(48),
          ),
          child: SizedBox(
            height: 24,
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: widget.loading
                    ? SizedBox(
                        key: const ValueKey('loading'),
                        width: double.infinity,
                        child: const LinearProgressIndicator(),
                      )
                    : Text(
                        widget.hasNextStep
                            ? _step.nextStepText(L10n.of(context))
                            : _step.lastStepText(L10n.of(context)),
                        key: const ValueKey('text'),
                        textAlign: TextAlign.center,
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
