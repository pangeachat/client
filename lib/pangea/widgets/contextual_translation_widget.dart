import 'package:flutter/material.dart';
import 'package:fluffychat/pangea/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/controllers/contextual_definition_controller.dart';

class ContextualTranslationWidget extends StatefulWidget {
  final PangeaToken token;

  const ContextualTranslationWidget({Key? key, required this.token}) : super(key: key);

  @override
  _ContextualTranslationWidgetState createState() => _ContextualTranslationWidgetState();
}

class _ContextualTranslationWidgetState extends State<ContextualTranslationWidget> {
  late Future<String> _definition;

  @override
  void initState() {
    super.initState();
    _definition = _fetchDefinition();
  }

  Future<String> _fetchDefinition() async {
    if (widget.token.shouldDoWordMeaningActivity) {
      return '?';
    } else {
      final controller = ContextualDefinitionController(/* Pass necessary parameters */);
      final response = await controller.get(/* Pass necessary request model */);
      return response?.text ?? 'No definition found';
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _definition,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return CircularProgressIndicator();
        } else if (snapshot.hasError) {
          return Text('Error: ${snapshot.error}');
        } else {
          return ActionChip(
            avatar: Icon(Icons.translate),
            label: Text(snapshot.data ?? 'No definition found'),
            onPressed: () {
              // Handle chip click
            },
          );
        }
      },
    );
  }
}
