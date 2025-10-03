import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/bot/widgets/bot_face_svg.dart';
import 'package:fluffychat/pangea/token_info_feedback/token_info_feedback_repo.dart';
import 'package:fluffychat/pangea/token_info_feedback/token_info_feedback_request.dart';
import 'package:fluffychat/pangea/token_info_feedback/token_info_feedback_response.dart';
import 'package:fluffychat/pangea/toolbar/widgets/word_zoom/word_zoom_widget.dart';

class TokenInfoFeedbackDialog extends StatefulWidget {
  final TokenInfoFeedbackRequestData requestData;
  final String langCode;

  const TokenInfoFeedbackDialog({
    super.key,
    required this.requestData,
    required this.langCode,
  });

  @override
  State<TokenInfoFeedbackDialog> createState() =>
      _TokenInfoFeedbackDialogState();
}

class _TokenInfoFeedbackDialogState extends State<TokenInfoFeedbackDialog> {
  final TextEditingController _feedbackController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _feedbackController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  Future<void> _submitFeedback() async {
    if (_feedbackController.text.isEmpty) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final request = TokenInfoFeedbackRequest(
        userFeedback: _feedbackController.text,
        data: widget.requestData,
      );

      final TokenInfoFeedbackResponse response =
          await TokenInfoFeedbackRepo.submitFeedback(request);

      // TODO: edit token info based on the included updated info in the response

      if (mounted) {
        // TODO: figure out how to close the dialog and show a snackbar in the main UI
        // Seems to be closing the dialog first and then its not mounted anymore so snackbar fails
        Navigator.of(context).pop();
        _showSuccessSnackBar(response.userFriendlyMessage);
      }
    } catch (error) {
      if (mounted) {
        _showErrorSnackBar('Failed to submit feedback: $error');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const BotFace(
              width: 30,
              expression: BotExpression.idle,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message),
            ),
          ],
        ),
        duration: const Duration(seconds: 30),
        action: SnackBarAction(
          label: L10n.of(context).close,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  void _showErrorSnackBar(String error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error),
        backgroundColor: Theme.of(context).colorScheme.error,
        action: SnackBarAction(
          label: L10n.of(context).close,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedToken =
        widget.requestData.tokens[widget.requestData.selectedToken];
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 2.5, sigmaY: 2.5),
      child: Dialog(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20.0),
        ),
        child: SizedBox(
          width: 325.0,
          child: Column(
            spacing: 20.0,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header with title and close button
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    Expanded(
                      child: Text(
                        L10n.of(context).tokenInfoFeedbackDialogTitle,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(
                      width: 40.0,
                      height: 40.0,
                      child: Center(
                        child: Icon(Icons.flag_outlined),
                      ),
                    ),
                  ],
                ),
              ),
              // Content
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20.0,
                ),
                child: Column(
                  spacing: 20.0,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Placeholder for word card
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      child: Center(
                        child: WordZoomWidget(
                          token: selectedToken.text,
                          construct: selectedToken.vocabConstructID,
                          langCode: widget.langCode,
                        ),
                      ),
                    ),
                    // Description text
                    Text(
                      L10n.of(context).tokenInfoFeedbackDialogDesc,
                      textAlign: TextAlign.center,
                    ),
                    // Feedback text field
                    TextField(
                      controller: _feedbackController,
                      decoration: InputDecoration(
                        hintText: L10n.of(context).feedbackHint,
                      ),
                      keyboardType: TextInputType.multiline,
                      minLines: 1,
                      maxLines: 5,
                    ),
                    // Submit button
                    ElevatedButton(
                      onPressed:
                          (_feedbackController.text.isNotEmpty && !_isLoading)
                              ? _submitFeedback
                              : null,
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(L10n.of(context).feedbackButton),
                              ],
                            ),
                    ),
                    const SizedBox.shrink(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
