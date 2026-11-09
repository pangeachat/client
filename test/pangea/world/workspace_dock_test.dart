import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/routes/world/workspace_dock.dart';

/// The shell reserves the rail's drawn width at the left edge
/// (`WorkspaceShell.railGutter`): the rail plus [WorkspaceDock.borderWidth] on
/// each side. When the dock's border and that constant disagree, a left panel
/// no longer sits as far from the rail as a right panel from the cluster
/// (#9778).
void main() {
  testWidgets('the dock is its child plus its border on each side', (
    tester,
  ) async {
    const childWidth = 81.0;
    await tester.pumpWidget(
      const MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: WorkspaceDock(child: SizedBox(width: childWidth, height: 40)),
        ),
      ),
    );

    expect(
      tester.getSize(find.byType(WorkspaceDock)).width,
      childWidth + WorkspaceDock.borderWidth * 2,
    );
  });
}
