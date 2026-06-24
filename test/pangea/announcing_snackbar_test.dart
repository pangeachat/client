import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/widgets/announcing_snackbar.dart';

void main() {
  // The announcing snackbar derives its screen-reader text from the SnackBar
  // content; verify the extraction so announcements stay meaningful (#7203).
  group('snackBarAnnouncementText', () {
    test('reads a plain Text content', () {
      expect(snackBarAnnouncementText(const Text('Saved')), 'Saved');
    });

    test('prefers semanticsLabel over the visible text', () {
      expect(
        snackBarAnnouncementText(
          const Text('5', semanticsLabel: 'five new messages'),
        ),
        'five new messages',
      );
    });

    test('reads a Text built from a span', () {
      expect(
        snackBarAnnouncementText(const Text.rich(TextSpan(text: 'Copied'))),
        'Copied',
      );
    });

    test('reads RichText content', () {
      expect(
        snackBarAnnouncementText(
          RichText(
            textDirection: TextDirection.ltr,
            text: const TextSpan(text: 'Update available'),
          ),
        ),
        'Update available',
      );
    });

    test(
      'returns null for non-text content (caller must announce explicitly)',
      () {
        expect(snackBarAnnouncementText(const Icon(Icons.error)), isNull);
      },
    );
  });
}
