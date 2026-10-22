import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/navigation/token_params/objective_token.dart';

/// The Mission detail token (#9559): it carries the course the detail was
/// opened from, so a Mission two courses share shows that course — and a
/// link from before the course field still opens.
void main() {
  test('a mission and its course round-trip', () {
    const param = ObjectiveTokenParam(
      missionId: 'lo-1',
      courseId: '!course:server.org',
    );
    expect(ObjectiveTokenParam.parse(param.build()), param);
  });

  test('a mission alone round-trips with no course', () {
    const param = ObjectiveTokenParam(missionId: 'lo-1');
    final parsed = ObjectiveTokenParam.parse(param.build());
    expect(parsed.missionId, 'lo-1');
    expect(parsed.courseId, isNull);
  });

  test('an old link of just the mission id still parses', () {
    final parsed = ObjectiveTokenParam.parse(
      '791b73f1-82d9-4d20-955b-df09120c1b14',
    );
    expect(parsed.missionId, '791b73f1-82d9-4d20-955b-df09120c1b14');
    expect(parsed.courseId, isNull);
  });
}
