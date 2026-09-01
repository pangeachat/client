import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/widgets/star_rain_widget.dart';

void main() {
  test('star rain motion stays under the WCAG 2.2.2 five-second limit', () {
    // Auto-starting motion that runs longer than five seconds over content the
    // user is reading needs a pause/stop/hide control. The celebration has no
    // such control by design, so it has to end first.
    final total = StarRainWidget.rainDuration + StarRainWidget.opacityDuration;
    expect(total, lessThan(const Duration(seconds: 5)));
  });
}
