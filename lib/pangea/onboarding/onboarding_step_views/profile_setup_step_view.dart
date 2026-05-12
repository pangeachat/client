import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:file_picker/file_picker.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/url_image_widget.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/profile_setup_onboarding_step.dart';
import 'package:fluffychat/utils/file_selector.dart';
import 'package:fluffychat/widgets/matrix.dart';

class _AvatarInfo {
  final Uri? avatarUrl;
  final Uint8List? avatarBytes;

  const _AvatarInfo({this.avatarUrl, this.avatarBytes});
}

class ProfileSetupStepView extends StatefulWidget {
  final ProfileSetupOnboardingStep step;

  const ProfileSetupStepView({super.key, required this.step});

  @override
  ProfileSetupStepViewState createState() => ProfileSetupStepViewState();
}

class ProfileSetupStepViewState extends State<ProfileSetupStepView> {
  late final ProfileSetupOnboardingStep _step;

  final TextEditingController _displayNameController = TextEditingController();

  final ValueNotifier<_AvatarInfo> _avatarNotifier = ValueNotifier(
    _AvatarInfo(),
  );

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
    _avatarNotifier.value = _AvatarInfo(avatarUrl: url);
  }

  void _setAvatarBytes(Uint8List bytes) {
    _step.setAvatarBytes(bytes);
    _avatarNotifier.value = _AvatarInfo(avatarBytes: bytes);
  }

  Future<void> _setDefaultProfileInfo() async {
    final client = Matrix.of(context).client;
    final userID = client.userID!;

    final profile = await client.fetchOwnProfile();
    final avatarUrl = profile.avatarUrl;
    if (avatarUrl != null) {
      _setAvatarUrl(avatarUrl);
    }

    final displayName = profile.displayName ?? userID.localpart ?? userID;
    _step.setDisplayName(displayName);
    _displayNameController.text = displayName;
  }

  Future<void> _uploadAvatarImage() async {
    final picked = await selectFiles(
      context,
      allowMultiple: false,
      type: FileType.image,
    );
    final pickedFile = picked.firstOrNull;
    if (pickedFile == null) return;
    final bytes = await pickedFile.readAsBytes();
    _setAvatarBytes(bytes);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ValueListenableBuilder(
          valueListenable: _avatarNotifier,
          builder: (context, _, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 110.0,
                width: 110.0,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 100.0,
                      height: 100.0,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(100.0),
                        color: theme.disabledColor,
                      ),
                      child: _step.avatarUrl != null
                          ? ImageByUrl(imageUrl: _step.avatarUrl)
                          : _step.avatarBytes != null
                          ? Image.memory(_step.avatarBytes!)
                          : SizedBox(),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: IconButton.filled(
                        icon: Icon(Symbols.upload),
                        onPressed: _uploadAvatarImage,
                        style: IconButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12.0),
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
                    .map(
                      (avatarUrl) => InkWell(
                        borderRadius: BorderRadius.circular(100.0),
                        onTap: () => _setAvatarUrl(avatarUrl),
                        child: SizedBox(
                          height: 32.0,
                          width: 32.0,
                          child: ImageByUrl(
                            imageUrl: avatarUrl,
                            borderRadius: BorderRadius.circular(100.0),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
        SizedBox(height: 12.0),
        Text(
          L10n.of(context).displayName,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 8.0),
        ValueListenableBuilder(
          valueListenable: _displayNameController,
          builder: (context, text, _) =>
              TextField(controller: _displayNameController),
        ),
      ],
    );
  }
}
