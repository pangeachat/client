import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/pangea/common/widgets/choice_animation.dart';

/// The pop or wobble a choice plays when it is selected or graded must not
/// touch its controller once the choice is gone. A practice card advances
/// while the animation is still finishing, so the animation's last tick and
/// the build that removes the choice land in the same frame (CLIENT-ETE,
/// #9202).
void main() {
  testWidgets('a choice removed as its animation ends leaves no error', (
    tester,
  ) async {
    late StateSetter host;
    var selected = false;
    var shown = true;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: StatefulBuilder(
          builder: (context, setState) {
            host = setState;
            return shown
                ? ChoiceAnimationWidget(
                    isSelected: selected,
                    isCorrect: true,
                    child: const SizedBox.square(dimension: 10),
                  )
                : const SizedBox.shrink();
          },
        ),
      ),
    );

    // Selecting the choice starts the pop.
    host(() => selected = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    // One frame both finishes the pop and removes the choice. The engine runs
    // the tick, then the build that disposes the widget, and only then the
    // microtasks the finish queued, so those run against a disposed
    // controller. `pump` would flush the microtasks between the two phases and
    // hide that order, so the frame is driven phase by phase.
    host(() => shown = false);
    tester.binding.handleBeginFrame(
      Duration(
        milliseconds:
            tester.binding.clock.now().millisecondsSinceEpoch +
            choiceArrayAnimationDuration,
      ),
    );
    tester.binding.handleDrawFrame();
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
