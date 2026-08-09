import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/navigation/panel_focus.dart';

void main() {
  group('PanelFocusController', () {
    test('notifies once on each distinct set', () {
      final c = PanelFocusController.instance;
      c.set(null); // known baseline before listening
      var notifications = 0;
      void listener() => notifications++;
      c.addListener(listener);
      addTearDown(() => c.removeListener(listener));

      c.set('room:%21a');
      c.set('room:%21b');

      expect(notifications, 2);
      expect(c.focusedLeftToken, 'room:%21b');
    });

    test('does not notify when the token is unchanged', () {
      final c = PanelFocusController.instance;
      c.set('room:%21x'); // baseline before listening
      var notifications = 0;
      void listener() => notifications++;
      c.addListener(listener);
      addTearDown(() => c.removeListener(listener));

      c.set('room:%21x');
      c.set('room:%21x');

      expect(notifications, 0);
    });
  });
}
