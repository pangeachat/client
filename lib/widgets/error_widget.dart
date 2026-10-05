import 'package:flutter/material.dart';

import 'package:fluffychat/utils/error_reporter.dart';

class FluffyChatErrorWidget extends StatefulWidget {
  final FlutterErrorDetails details;
  const FluffyChatErrorWidget(this.details, {super.key});

  @override
  State<FluffyChatErrorWidget> createState() => _FluffyChatErrorWidgetState();
}

class _FluffyChatErrorWidgetState extends State<FluffyChatErrorWidget> {
  static final Set<String> knownExceptions = {};
  @override
  void initState() {
    super.initState();

    if (knownExceptions.contains(widget.details.exception.toString())) {
      return;
    }
    knownExceptions.add(widget.details.exception.toString());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // #Pangea
      // related sentry issue: https://pangea-chat.sentry.io/issues/5970490357
      if (!context.mounted) return;
      // Pangea#
      ErrorReporter(
        context,
        'Error Widget',
      ).onErrorCallback(widget.details.exception, widget.details.stack);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.errorContainer,
      child: Placeholder(
        child: Center(
          child: Material(
            color: colorScheme.surface.withAlpha(230),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }
}
