import 'package:flutter/material.dart';

import 'package:collection/collection.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/constants/preset_avatars.dart';
import 'package:fluffychat/widgets/url_image_widget.dart';

/// Row of the preset Pangea avatars. Used inline in the onboarding
/// profile-setup step and inside [showPresetAvatarPickerDialog].
class PresetAvatarRow extends StatelessWidget {
  final void Function(Uri) onSelected;
  final double size;
  final double spacing;

  const PresetAvatarRow({
    super.key,
    required this.onSelected,
    this.size = 32.0,
    this.spacing = 6.0,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: spacing,
      mainAxisSize: MainAxisSize.min,
      children: PresetAvatars.all
          .mapIndexed(
            (index, avatarUrl) => Semantics(
              label: PresetAvatars.description(L10n.of(context), index),
              button: true,
              child: InkWell(
                borderRadius: BorderRadius.circular(100.0),
                onTap: () => onSelected(avatarUrl),
                child: SizedBox(
                  height: size,
                  width: size,
                  child: ImageByUrl(
                    width: size,
                    imageUrl: avatarUrl,
                    borderRadius: BorderRadius.circular(100.0),
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

/// Opens a dialog with the preset Pangea avatars and resolves to the
/// chosen preset's URL, or null if dismissed.
Future<Uri?> showPresetAvatarPickerDialog(BuildContext context) =>
    showDialog<Uri>(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog.adaptive(
        title: Text(L10n.of(context).choosePangeaAvatar),
        content: PresetAvatarRow(
          size: 48.0,
          onSelected: (url) => Navigator.of(context).pop<Uri>(url),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: Text(L10n.of(context).cancel),
          ),
        ],
      ),
    );
