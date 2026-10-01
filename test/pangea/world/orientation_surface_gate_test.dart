import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/navigation/panel_types_enum.dart';
import 'package:fluffychat/routes/world/world_map.dart';

/// The gate deciding whether the map is showing behind whatever else is open,
/// and so whether the orientation tutorials may fire or resume.
///
/// The regression this locks (#8184): the gate demanded that NO left panel be
/// open. The app opens with the chat list showing, so on arrival — the one
/// moment the orientation sequence exists for — it could not fire, and only
/// appeared if the learner happened to close everything. A left panel does not
/// hide the map: on a wide screen it is a column beside it, and in
/// single-column mode the sections ride the nav cavity over it.
void main() {
  group('orientationSurfaceGate', () {
    bool gate({
      bool isWorldScope = true,
      bool mapIsDrawingPins = true,
      bool hasRightPanel = false,
      Iterable<PanelTypesEnum> leftPanels = const [],
      bool isSingleColumn = false,
    }) => orientationSurfaceGate(
      isWorldScope: isWorldScope,
      mapIsDrawingPins: mapIsDrawingPins,
      hasRightPanel: hasRightPanel,
      leftPanels: leftPanels,
      isSingleColumn: isSingleColumn,
    );

    test('a bare world map with pins is showing', () {
      expect(gate(), isTrue);
    });

    test('the chat list open does NOT withhold it — the app opens this way, '
        'and the panel is a column beside the map', () {
      expect(gate(leftPanels: const [PanelTypesEnum.chats]), isTrue);
    });

    test('an activity plan does not withhold it — that is the pin step being '
        'answered', () {
      expect(gate(leftPanels: const [PanelTypesEnum.activity]), isTrue);
    });

    test('a course panel withholds it — the course tutorial owns that '
        'surface', () {
      expect(gate(leftPanels: const [PanelTypesEnum.course]), isFalse);
      expect(gate(leftPanels: const [PanelTypesEnum.coursepage]), isFalse);
    });

    test('the Courses hub withholds it too', () {
      expect(gate(leftPanels: const [PanelTypesEnum.addcourse]), isFalse);
    });

    test('any right panel withholds it — the learner is doing something '
        'else', () {
      expect(gate(hasRightPanel: true), isFalse);
      expect(
        gate(hasRightPanel: true, leftPanels: const [PanelTypesEnum.chats]),
        isFalse,
      );
    });

    test('a live chat withholds it on a single column, where it draws '
        'full-screen over the map', () {
      expect(
        gate(isSingleColumn: true, leftPanels: const [PanelTypesEnum.room]),
        isFalse,
      );
      expect(
        gate(isSingleColumn: true, leftPanels: const [PanelTypesEnum.session]),
        isFalse,
      );
    });

    test('the same live chat is just another column on a wide screen', () {
      expect(gate(leftPanels: const [PanelTypesEnum.room]), isTrue);
    });

    test('a course-scoped map is never the surface — the step claims every '
        'activity in the language lives here', () {
      expect(gate(isWorldScope: false), isFalse);
      expect(
        gate(isWorldScope: false, leftPanels: const [PanelTypesEnum.chats]),
        isFalse,
      );
    });

    test('a map drawing no pins is not ready, whatever is open', () {
      expect(gate(mapIsDrawingPins: false), isFalse);
    });
  });
}
