import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/world/settings_page_enum.dart';

/// Every settings detail must end up with exactly ONE header: the shared
/// PanelCardHeader by default, or its own chrome when it opts out via
/// `addHeader == false`. #7763 flattened the wrapper away for every page,
/// leaving the classic pages with no title and no way out; these tests pin
/// both halves of the contract.
void main() {
  group('SettingsPageEnum.addHeader', () {
    // Pages whose views render NO chrome of their own — dropping the shared
    // header strands the user with no title and no close control.
    const needsSharedHeader = {
      SettingsPageEnum.learning,
      SettingsPageEnum.style,
      SettingsPageEnum.notifications,
      SettingsPageEnum.devices,
      SettingsPageEnum.chat,
      SettingsPageEnum.security,
      SettingsPageEnum.password,
      SettingsPageEnum.ignore,
      SettingsPageEnum.profile,
      SettingsPageEnum.menu,
    };

    // Pages that build their own header AND take the panel's closeButton —
    // wrapping them too would draw two headers.
    const rendersOwnHeader = {
      SettingsPageEnum.email, // own PanelHeader (+ add-email action)
      SettingsPageEnum.subscription, // own AppBar per leaf
    };

    for (final page in needsSharedHeader) {
      test('${page.name} takes the shared header', () {
        expect(page.addHeader, isTrue);
      });
    }

    for (final page in rendersOwnHeader) {
      test('${page.name} opts out (renders its own)', () {
        expect(page.addHeader, isFalse);
      });
    }

    test('every enum value is classified by these tests', () {
      expect(
        {...needsSharedHeader, ...rendersOwnHeader},
        containsAll(SettingsPageEnum.values),
        reason: 'a new SettingsPageEnum needs a header decision here',
      );
    });
  });

  group('SettingsPageEnum.fromString', () {
    test('subscription leaves all resolve to subscription, not menu', () {
      // A leaf falling through to `menu` (addHeader true) would take the shared
      // header on top of the AppBar it draws itself.
      for (final sub in [
        'subscription',
        'subscription/history',
        'subscription/discount',
        'subscription/selected',
      ]) {
        expect(
          SettingsPageEnum.fromString(sub),
          SettingsPageEnum.subscription,
          reason: '$sub must not fall through to menu',
        );
      }
    });

    test('classic pages resolve to themselves', () {
      expect(
        SettingsPageEnum.fromString('learning'),
        SettingsPageEnum.learning,
      );
      expect(
        SettingsPageEnum.fromString('security'),
        SettingsPageEnum.security,
      );
      expect(
        SettingsPageEnum.fromString('security/password'),
        SettingsPageEnum.password,
      );
      expect(
        SettingsPageEnum.fromString('security/3pid'),
        SettingsPageEnum.email,
      );
      expect(
        SettingsPageEnum.fromString('security/ignorelist/@a:b.com'),
        SettingsPageEnum.ignore,
      );
    });

    test('null and unknown degrade to the menu', () {
      expect(SettingsPageEnum.fromString(null), SettingsPageEnum.menu);
      expect(SettingsPageEnum.fromString('nope'), SettingsPageEnum.menu);
    });
  });
}
