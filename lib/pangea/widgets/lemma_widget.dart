import 'package:flutter/material.dart';
import 'package:fluffychat/pangea/models/pangea_token_model.dart';

class LemmaWidget extends StatefulWidget {
  final PangeaToken token;

  const LemmaWidget({Key? key, required this.token}) : super(key: key);

  @override
  _LemmaWidgetState createState() => _LemmaWidgetState();
}

class _LemmaWidgetState extends State<LemmaWidget> {
  late Future<String> _lemmaText;

  @override
  void initState() {
    super.initState();
    _lemmaText = _fetchLemmaText();
  }

  Future<String> _fetchLemmaText() async {
    if (widget.token.shouldDoLemmaActivity()) {
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
          return CircularProgressIndicator();
        } else if (snapshot.hasError) {
          return Text('Error: ${snapshot.error}');
        } else {
          return ActionChip(
            avatar: Icon(Icons.book),
            label: Text(snapshot.data ?? 'No lemma found'),
            onPressed: () {
              // Handle chip click
            },
          );
        }
      },
    );
  }
}
