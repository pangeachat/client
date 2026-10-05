import 'package:flutter/material.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/activity_sessions/activity_media_block.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/chat/activity_sessions/activity_media_carousel.dart';
import 'package:fluffychat/widgets/mxc_image_viewer.dart';
import 'one_node_control.dart';

/// #9356 — the activity image sits at the top of the chat as a square crop,
/// and tapping it opens the whole image full screen.
void main() {
  // ImageByUrl checks each URL against the CMS host, which Environment reads
  // from dotenv.
  setUpAll(() => dotenv.testLoad(mergeWith: <String, String>{}));

  // Hosts outside AppConfig's image allow-list render a blurhash, so the test
  // needs no network.
  const fullUrl = 'https://example.com/full.jpg';
  const mediumUrl = 'https://example.com/medium.jpg';
  final fallbackUrl = Uri.parse('https://example.com/legacy.jpg');

  const image = ActivityMediaBlock(
    blockType: 'image',
    resolvedUrl: fullUrl,
    resolvedMediumUrl: mediumUrl,
  );

  Widget subject(ActivityMediaCarousel carousel, {Widget? below}) =>
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          // A list, like the chat timeline: under a Scrollable, loose text
          // merges into the nearest semantics node.
          body: ListView(
            children: [
              Column(children: [carousel, ?below]),
            ],
          ),
        ),
      );

  Future<Uri> tapAndReadViewerUrl(WidgetTester tester) async {
    await tester.tap(find.bySemanticsLabel('View image'));
    await tester.pumpAndSettle();
    return tester.widget<MxcImageViewer>(find.byType(MxcImageViewer)).mxContent;
  }

  testWidgets('an image is one button named View image', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      subject(const ActivityMediaCarousel(media: [image])),
    );
    await tester.pumpAndSettle();

    expectOneNodeControl(tester, 'View image');
    handle.dispose();
  });

  // In the chat the description sits right below the carousel, and the button
  // absorbed its text into its own name.
  testWidgets('text beside the image stays out of the button name', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      subject(
        const ActivityMediaCarousel(media: [image]),
        below: const Text('Plan where to meet'),
      ),
    );
    await tester.pumpAndSettle();

    expectOneNodeControl(tester, 'View image');
    handle.dispose();
  });

  testWidgets('tapping an image opens its full-resolution file', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      subject(const ActivityMediaCarousel(media: [image])),
    );
    await tester.pumpAndSettle();

    expect(await tapAndReadViewerUrl(tester), Uri.parse(fullUrl));
    handle.dispose();
  });

  testWidgets('tapping the legacy single image opens it', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      subject(ActivityMediaCarousel(media: [], fallbackImageUrl: fallbackUrl)),
    );
    await tester.pumpAndSettle();

    expect(await tapAndReadViewerUrl(tester), fallbackUrl);
    handle.dispose();
  });

  testWidgets('an activity with no image offers nothing to view', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(subject(const ActivityMediaCarousel(media: [])));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('View image'), findsNothing);
    handle.dispose();
  });
}
