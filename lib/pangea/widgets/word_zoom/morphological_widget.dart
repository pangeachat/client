import 'dart:developer';

import 'package:fluffychat/pangea/models/pangea_token_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

class MorphologicalListWidget extends StatefulWidget {
  final PangeaToken token;

  const MorphologicalListWidget({
    super.key,
    required this.token,
  });

  @override
  _MorphologicalListWidgetState createState() =>
      _MorphologicalListWidgetState();
}

class _MorphologicalListWidgetState extends State<MorphologicalListWidget> {
  // TODO: make this is a list of morphological features icons based on MorphActivityGenerator.getSequence
  // For each item in the sequence,
  //    if shouldDoActivity is true, show the template icon then stop
  //    if shouldDoActivity is false, show the actual icon and value then go to the next item

  @override
  void initState() {
    super.initState();
  }

  Future<String> _fetchMorphValue(String feature) async {
    if (widget.token.shouldDoMorphActivity(feature)) {
      return '?';
    } else {
      return widget.token.morph[feature] ?? 'No value found';
    }
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
    return const SizedBox();
  }
}
