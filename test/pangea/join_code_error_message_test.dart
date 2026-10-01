import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/join_codes/knock_with_code_extension.dart';
import 'package:fluffychat/features/join_codes/space_code_controller.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/network/pangea_http_exception.dart';

/// The join-with-code error mapping (#8831). Every failure used to read as
/// "No chat or course found with that code", so a valid code the server could
/// not invite to (500 `ORG.PANGEA.INVITE_FAILED`, synapse-pangea-chat#197)
/// sent the learner back to retype a code that was right.
void main() {
  PangeaHttpException http(int status, {String? detail}) => PangeaHttpException(
    statusCode: status,
    method: 'POST',
    path: '/_synapse/client/pangea/v1/knock_with_code',
    detail: detail,
  );

  group('SpaceCodeController.isCodeNotFound', () {
    test(
      'is true for the 404 CODE_NOT_FOUND, a legacy 400, and the client-side empty result',
      () {
        expect(
          SpaceCodeController.isCodeNotFound(
            http(404, detail: 'ORG.PANGEA.CODE_NOT_FOUND'),
          ),
          isTrue,
        );
        expect(SpaceCodeController.isCodeNotFound(http(400)), isTrue);
        expect(SpaceCodeController.isCodeNotFound(NotFoundException()), isTrue);
      },
    );

    test(
      'is false for a server-side invite failure and for anything untyped',
      () {
        expect(
          SpaceCodeController.isCodeNotFound(
            http(500, detail: 'ORG.PANGEA.INVITE_FAILED'),
          ),
          isFalse,
        );
        expect(SpaceCodeController.isCodeNotFound(http(429)), isFalse);
        expect(SpaceCodeController.isCodeNotFound(Exception('join')), isFalse);
      },
    );
  });

  group('SpaceCodeController.joinErrorMessage', () {
    late BuildContext context;

    setUp(() => TestWidgetsFlutterBinding.ensureInitialized());

    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      );
      // L10n's delegate resolves from a deferred library, so nothing is in the
      // tree until localizations finish loading.
      await tester.pumpAndSettle();
    }

    testWidgets(
      'a wrong code reads as not found, in the surface\'s own words',
      (tester) async {
        await pump(tester);
        expect(
          SpaceCodeController.joinErrorMessage(context, http(404)),
          L10n.of(context).unableToFindRoom,
        );
        expect(
          SpaceCodeController.joinErrorMessage(
            context,
            NotFoundException(),
            notFoundError: 'not the code',
          ),
          'not the code',
        );
      },
    );

    testWidgets('a ban reads as removed', (tester) async {
      await pump(tester);
      expect(
        SpaceCodeController.joinErrorMessage(
          context,
          BannedFromRoomException(),
          notFoundError: 'not the code',
        ),
        L10n.of(context).removedFromCourseError,
      );
    });

    testWidgets(
      'a valid code the server could not invite to never blames the code',
      (tester) async {
        await pump(tester);
        final message = SpaceCodeController.joinErrorMessage(
          context,
          http(500, detail: 'ORG.PANGEA.INVITE_FAILED'),
          notFoundError: 'not the code',
        );
        expect(message, L10n.of(context).unableToJoinCourseError);
        expect(message, isNot(L10n.of(context).unableToFindRoom));
      },
    );
  });
}
