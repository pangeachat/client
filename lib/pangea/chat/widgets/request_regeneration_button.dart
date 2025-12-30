import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';

class RequestRegenerationButton extends StatelessWidget {
  final Color textColor;
  final VoidCallback onPressed;

  const RequestRegenerationButton({
    super.key,
    required this.textColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 8.0,
        left: 16.0,
        right: 16.0,
      ),
      child: TextButton(
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size(
            0,
            0,
          ),
        ),
        onPressed: onPressed,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 4.0,
          children: [
            Icon(
              Icons.refresh,
              color: textColor.withAlpha(
                164,
              ),
              size: 14,
            ),
            Text(
              L10n.of(
                context,
              ).requestRegeneration,
              style: TextStyle(
                color: textColor.withAlpha(
                  164,
                ),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
