import 'dart:developer';

import 'package:fluffychat/pangea/enum/activity_type_enum.dart';
import 'package:fluffychat/pangea/enum/analytics/morph_categories_enum.dart';
import 'package:fluffychat/pangea/models/pangea_token_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

class MorphologicalListWidget extends StatefulWidget {
  final String? selectedMorphFeature;
  final PangeaToken token;
  final Function(String) onPressed;
  final int completedActivities;

  const MorphologicalListWidget({
    super.key,
    required this.selectedMorphFeature,
    required this.token,
    required this.onPressed,
    required this.completedActivities,
  });

  @override
  MorphologicalListWidgetState createState() => MorphologicalListWidgetState();
}

class MorphologicalListWidgetState extends State<MorphologicalListWidget> {
  // TODO: make this is a list of morphological features icons based on MorphActivityGenerator.getSequence
  // For each item in the sequence,
  //    if shouldDoActivity is true, show the template icon then stop
  //    if shouldDoActivity is false, show the actual icon and value then go to the next item
  final Map<String, bool> _morphEnabledStatus = {};

  @override
  void initState() {
    super.initState();
    _setMorphEnabledStatus();
  }

  @override
  void didUpdateWidget(covariant MorphologicalListWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.token != oldWidget.token ||
        widget.completedActivities != oldWidget.completedActivities) {
      _setMorphEnabledStatus();
    }
  }

  Future<void> _setMorphEnabledStatus() async {
    _morphEnabledStatus.clear();
    for (final entry in widget.token.morph.entries) {
      final shouldDoActivity = widget.token.shouldDoMorphActivity(entry.key);
      final canGenerateDistractors = await widget.token.canGenerateDistractors(
        ActivityTypeEnum.morphId,
        morphFeature: entry.key,
        morphTag: entry.value,
      );
      _morphEnabledStatus[entry.key] =
          shouldDoActivity && canGenerateDistractors;
    }
    if (mounted) setState(() {});
  }

  // TODO Use the icons that Khue is creating
  IconData _getIconForMorphFeature(String feature) {
    // Define a function to get the icon based on the universal dependency morphological feature (key)
    switch (feature) {
      case 'Number':
        // google material 123 icon
        return Icons.format_list_numbered;
      case 'Gender':
        return Icons.wc;
      case 'Tense':
        return Icons.access_time;
      case 'Mood':
        return Icons.mood;
      case 'Person':
        return Icons.person;
      case 'Case':
        return Icons.format_list_bulleted;
      case 'Degree':
        return Icons.trending_up;
      case 'VerbForm':
        return Icons.text_format;
      case 'Voice':
        return Icons.record_voice_over;
      case 'Aspect':
        return Icons.aspect_ratio;
      case 'PronType':
        return Icons.text_fields;
      case 'NumType':
        return Icons.format_list_numbered;
      case 'Poss':
        return Icons.account_balance;
      case 'Reflex':
        return Icons.refresh;
      case 'Foreign':
        return Icons.language;
      case 'Abbr':
        return Icons.text_format;
      case 'NounType':
        return Symbols.abc;
      default:
        debugger(when: kDebugMode);
        return Icons.help_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      children: widget.token.morph.entries.map((entry) {
        return Padding(
          padding: const EdgeInsets.all(2.0),
          child: MorphologicalActivityButton(
            onPressed: widget.onPressed,
            morphCategory: entry.key,
            icon: _getIconForMorphFeature(entry.key),
            isUnlocked: _morphEnabledStatus[entry.key] ?? false,
            isSelected: widget.selectedMorphFeature == entry.key,
          ),
        );
      }).toList(),
    );
  }
}

class MorphologicalActivityButton extends StatelessWidget {
  final Function(String) onPressed;
  final String morphCategory;
  final IconData icon;

  final bool isUnlocked;
  final bool isSelected;

  const MorphologicalActivityButton({
    required this.onPressed,
    required this.morphCategory,
    required this.icon,
    this.isUnlocked = true,
    this.isSelected = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Tooltip(
          message: getMorphologicalCategoryCopy(
            morphCategory,
            context,
          ),
          child: OutlinedButton(
            onPressed: () {
              onPressed(morphCategory);
            },
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                color: isSelected
                    ? Colors.green
                    : isUnlocked
                        ? Colors.blue
                        : Colors.grey,
                width: 2,
              ),
            ),
            child: Icon(icon, size: 20),
          ),
        ),
      ],
    );
  }
}
