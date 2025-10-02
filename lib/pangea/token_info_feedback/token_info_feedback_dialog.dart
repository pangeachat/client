import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/bot/widgets/bot_face_svg.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/lemmas/lemma_info_response.dart';
import 'package:fluffychat/pangea/token_info_feedback/token_info_feedback_repo.dart';
import 'package:fluffychat/pangea/token_info_feedback/token_info_feedback_request.dart';
import 'package:fluffychat/pangea/token_info_feedback/token_info_feedback_response.dart';

class TokenInfoFeedbackDialog extends StatefulWidget {
  final String userId;
  final String roomId;
  final String fullText;
  final String detectedLanguage;
  final List<PangeaToken> tokens;
  final int selectedToken;
  final LemmaInfoResponse? lemmaInfo;
  final String? phonetics;
  final String wordCardL1;

  const TokenInfoFeedbackDialog({
    super.key,
    required this.userId,
    required this.roomId,
    required this.fullText,
    required this.detectedLanguage,
    required this.tokens,
    required this.selectedToken,
    this.lemmaInfo,
    this.phonetics,
    required this.wordCardL1,
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
        userId: widget.userId,
        roomId: widget.roomId,
        fullText: widget.fullText,
        detectedLanguage: widget.detectedLanguage,
        tokens: widget.tokens,
        selectedToken: widget.selectedToken,
        lemmaInfo: widget.lemmaInfo,
        phonetics: widget.phonetics,
        userFeedback: _feedbackController.text,
        wordCardL1: widget.wordCardL1,
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
                    const Expanded(
                      child: Text(
                        'Word Information Feedback', // Could be localized later
                        style: TextStyle(
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
                      width: double.infinity,
                      height: 120,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      child: const Center(
                        child: Text(
                          'Word Card Placeholder',
                          style: TextStyle(
                            color: Colors.grey,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ),
                    // Description text
                    const Text(
                      'AI makes mistakes. Please describe any issues you found with the information above.',
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
