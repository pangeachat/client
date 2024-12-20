import 'package:fluffychat/pangea/models/pangea_token_model.dart';
import 'package:flutter/material.dart';

class LemmaWidget extends StatefulWidget {
  final PangeaToken token;
  final VoidCallback onPressed;

  final String? lemma;
  final Function(String) setLemma;

  const LemmaWidget({
    super.key,
    required this.token,
    required this.onPressed,
    this.lemma,
    required this.setLemma,
  });

  @override
  LemmaWidgetState createState() => LemmaWidgetState();
}

class LemmaWidgetState extends State<LemmaWidget> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: IconButton(
        onPressed: () {
          widget.onPressed();
          if (widget.lemma == null) {
            debugPrint("SETTING LEMMA!!!!! IN BUTTON");
            widget.setLemma(widget.token.lemma.text);
          }
        },
        icon: Text(widget.token.xpEmoji),
      ),
    );
  }
}
