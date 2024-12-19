import 'package:fluffychat/pangea/enum/activity_type_enum.dart';
import 'package:fluffychat/pangea/models/pangea_token_model.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

class LemmaWidget extends StatefulWidget {
  final PangeaToken token;

  const LemmaWidget({super.key, required this.token});

  @override
  _LemmaWidgetState createState() => _LemmaWidgetState();
}

class _LemmaWidgetState extends State<LemmaWidget> {
  late Future<String> _lemmaText;

  //TODO - on click, go to the lemma page OR give practice activity, based on shouldDoActivity
  // always show seed/sprout/flower icon

  @override
  void initState() {
    super.initState();
    _lemmaText = _fetchLemmaText();
  }

  Future<String> _fetchLemmaText() async {
    if (widget.token.shouldDoActivity(
        a: ActivityTypeEnum.lemmaId, feature: null, tag: null)) {
      return '?';
    } else {
      return widget.token.lemma.text;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _lemmaText,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const CircularProgressIndicator();
        } else if (snapshot.hasError) {
          return Text('Error: ${snapshot.error}');
        } else {
          return ActionChip(
            avatar: const Icon(Symbols.dictionary),
            label: Text(snapshot.data ?? 'No lemma found'),
            shape: const RoundedRectangleBorder(
              side: BorderSide.none,
              borderRadius: BorderRadius.all(
                Radius.circular(8),
              ), // Optional: Adjust radius if needed
            ),
            onPressed: () {
              // Handle chip click
            },
          );
        }
      },
    );
  }
}
