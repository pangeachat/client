import 'package:flutter/material.dart';
import 'package:fluffychat/pangea/models/pangea_token_model.dart';

class PartOfSpeechWidget extends StatefulWidget {
  final PangeaToken token;

  const PartOfSpeechWidget({Key? key, required this.token}) : super(key: key);

  @override
  _PartOfSpeechWidgetState createState() => _PartOfSpeechWidgetState();
}

class _PartOfSpeechWidgetState extends State<PartOfSpeechWidget> {
  late Future<String> _partOfSpeech;

  @override
  void initState() {
    super.initState();
    _partOfSpeech = _fetchPartOfSpeech();
  }

  Future<String> _fetchPartOfSpeech() async {
    if (widget.token.shouldDoPosActivity()) {
      return '?';
    } else {
      return widget.token.pos;
    }
  }

  IconData _getIconForPartOfSpeech(String pos) {
    switch (pos) {
      case 'NOUN':
        return Icons.nouns;
      case 'VERB':
        return Icons.verbs;
      case 'ADJ':
        return Icons.adjectives;
      case 'ADV':
        return Icons.adverbs;
      default:
        return Icons.help_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _partOfSpeech,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return CircularProgressIndicator();
        } else if (snapshot.hasError) {
          return Text('Error: ${snapshot.error}');
        } else {
          return ActionChip(
            avatar: Icon(_getIconForPartOfSpeech(widget.token.pos)),
            label: Text(snapshot.data ?? 'No part of speech found'),
            onPressed: () {
              // Handle chip click
            },
          );
        }
      },
    );
  }
}
