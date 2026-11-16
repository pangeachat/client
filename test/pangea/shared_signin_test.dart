import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/shared_signin/shared_signin.dart';

const _state = '0123456789abcdef0123456789abcdef';

void main() {
  group('state', () {
    test('is 128 random bits as 32 hex characters', () {
      final state = newHandoffState(Random(1));
      expect(state, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(newHandoffState(), isNot(newHandoffState()));
    });

    test('matches only the same well-formed value', () {
      expect(statesMatch(_state, _state), isTrue);
      expect(statesMatch(_state, _state.replaceFirst('0', '1')), isFalse);
      expect(statesMatch(null, _state), isFalse);
      expect(statesMatch(_state, null), isFalse);
      expect(statesMatch('short', 'short'), isFalse);
    });
  });

  group('an arrival fragment', () {
    test('from the dashboard: a hint, nothing more', () {
      expect(parseHandoffArrival('from=dashboard'), isA<HandoffHint>());
    });

    test("the dashboard's request carries its state", () {
      final arrival = parseHandoffArrival('state=$_state');
      expect(arrival, isA<HandoffRequest>());
      expect((arrival as HandoffRequest).state, _state);
    });

    test('an answer carries a token, or none', () {
      final token = parseHandoffArrival('loginToken=t%2B1&state=$_state');
      expect(token, isA<HandoffAnswer>());
      expect((token as HandoffAnswer).loginToken, 't+1');
      final none = parseHandoffArrival('handoff=none&state=$_state');
      expect((none as HandoffAnswer).loginToken, isNull);
    });

    test('anything else is refused, not guessed at', () {
      for (final bad in [
        null,
        '',
        '/rooms',
        'from=elsewhere',
        'state=short',
        'loginToken=t',
        'loginToken=t&state=$_state&extra=1',
        'loginToken=&state=$_state',
        'handoff=maybe&state=$_state',
        'loginToken=t&handoff=none&state=$_state',
        'loginToken=t&loginToken=u&state=$_state',
        'state=%ZZ',
      ]) {
        expect(parseHandoffArrival(bad), isNull, reason: bad);
      }
    });
  });

  group('accepting a token', () {
    final answer = parseHandoffArrival('loginToken=tok&state=$_state');

    test("only with the state this tab saved", () {
      expect(acceptedHandoffToken(answer, _state), 'tok');
      expect(acceptedHandoffToken(answer, null), isNull);
      expect(
        acceptedHandoffToken(answer, _state.replaceFirst('0', 'f')),
        isNull,
      );
    });

    test('never from a hint, a request or a none', () {
      expect(acceptedHandoffToken(HandoffHint(), _state), isNull);
      expect(acceptedHandoffToken(HandoffRequest(_state), _state), isNull);
      expect(
        acceptedHandoffToken(
          parseHandoffArrival('handoff=none&state=$_state'),
          _state,
        ),
        isNull,
      );
    });
  });

  group('urls', () {
    test('the dashboard must be https, or http on this machine', () {
      expect(
        dashboardBase('https://admin.example.test/').toString(),
        'https://admin.example.test',
      );
      expect(
        dashboardBase('http://localhost:3000').toString(),
        'http://localhost:3000',
      );
      for (final bad in [
        null,
        '',
        'http://admin.example.test',
        'javascript:alert(1)',
        'https://u@admin.example.test',
        'https://admin.example.test/?x=1',
        'https://admin.example.test/#x',
      ]) {
        expect(dashboardBase(bad), isNull, reason: bad);
      }
    });

    test(
      "the answer goes only to the dashboard's fixed page, in the fragment",
      () {
        final dash = dashboardBase('https://admin.example.test')!;
        expect(
          dashboardAnswerUrl(dash, _state, loginToken: 'a+b&c'),
          'https://admin.example.test/auth/handoff/#loginToken=a%2Bb%26c&state=$_state',
        );
        expect(
          dashboardAnswerUrl(dash, _state),
          'https://admin.example.test/auth/handoff/#handoff=none&state=$_state',
        );
      },
    );

    test("the request to the dashboard's API names this app's origin", () {
      expect(
        dashboardSignInRequestUrl(
          'https://api.example.test',
          _state,
          'https://app.example.test',
        ),
        'https://api.example.test/api/auth/handoff/app'
        '?state=$_state&origin=https%3A%2F%2Fapp.example.test',
      );
    });
  });

  test('a signed-out visitor from the dashboard asks it once', () {
    bool should({
      bool hinted = true,
      bool tried = false,
      bool session = false,
      String bff = 'https://api.example.test',
    }) => shouldAskDashboard(
      isWeb: true,
      hinted: hinted,
      alreadyTried: tried,
      hasSession: session,
      teacherBffApi: bff,
    );
    expect(should(), isTrue);
    expect(should(hinted: false), isFalse);
    expect(should(tried: true), isFalse);
    expect(should(session: true), isFalse);
    expect(should(bff: ''), isFalse);
    expect(
      shouldAskDashboard(
        isWeb: false,
        hinted: true,
        alreadyTried: false,
        hasSession: false,
        teacherBffApi: 'https://api.example.test',
      ),
      isFalse,
    );
  });
}
