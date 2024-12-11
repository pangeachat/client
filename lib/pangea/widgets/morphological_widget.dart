import 'package:flutter/material.dart';
import 'package:fluffychat/pangea/models/pangea_token_model.dart';

class MorphologicalWidget extends StatefulWidget {
  final PangeaToken token;
  final String morphFeature;

  const MorphologicalWidget({
    Key? key,
    required this.token,
    required this.morphFeature,
  }) : super(key: key);

  @override
  _MorphologicalWidgetState createState() => _MorphologicalWidgetState();
}

class _MorphologicalWidgetState extends State<MorphologicalWidget> {
  late Future<String> _morphValue;

  @override
  void initState() {
    super.initState();
    _morphValue = _fetchMorphValue();
  }

  Future<String> _fetchMorphValue() async {
    if (widget.token.shouldDoMorphActivity(widget.morphFeature)) {
      return '?';
    } else {
      return widget.token.morph[widget.morphFeature] ?? 'No value found';
    }
  }

  IconData _getIconForMorphFeature(String feature) {
    // Define a function to get the icon based on the universal dependency morphological feature (key)
    switch (feature) {
      case 'Number':
        return Icons.format_list_numbered;
      case 'Gender':
        return Icons.wc;
      case 'Tense':
        return Icons.access_time;
      default:
        return Icons.help_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _morphValue,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return CircularProgressIndicator();
        } else if (snapshot.hasError) {
          return Text('Error: ${snapshot.error}');
        } else {
          return ActionChip(
            avatar: Icon(_getIconForMorphFeature(widget.morphFeature)),
            label: Text(snapshot.data ?? 'No value found'),
            onPressed: () {
              // Handle chip click
            },
          );
        }
      },
    );
  }
}
