import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/tutorials/tutorial_target.dart';
import 'package:fluffychat/widgets/matrix.dart';

int _mounts = 0;

class _Probe extends StatefulWidget {
  const _Probe();

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    _mounts++;
  }

  @override
  Widget build(BuildContext context) =>
      const SizedBox(width: 120.0, height: 40.0);
}

/// A target hosted the way the workspace hosts one: inside a [LayoutBuilder]
/// (so the subtree is built during layout, as the course card's reveal does)
/// under a host that is re-keyed when the panel's token changes.
Widget _host(String targetId, String token) => MaterialApp(
  home: Scaffold(
    body: LayoutBuilder(
      builder: (context, constraints) => Center(
        child: KeyedSubtree(
          key: ValueKey(token),
          child: TutorialTarget(targetId: targetId, child: const _Probe()),
        ),
      ),
    ),
  ),
);

void main() {
  setUp(() => _mounts = 0);

  testWidgets('re-keying the host remounts the child instead of moving it', (
    tester,
  ) async {
    await tester.pumpWidget(_host('target_swap', 'course'));
    expect(_mounts, 1);

    await tester.pumpWidget(_host('target_swap', 'course:chat'));

    // The registry's GlobalKey must not carry the child to the new host: a
    // subtree reparented from inside a LayoutBuilder's build mutates the
    // overlay mid-layout the moment it holds a shown OverlayPortal (#9046).
    expect(_mounts, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the registered key measures the child', (tester) async {
    await tester.pumpWidget(_host('target_rect', 'course'));

    final box = MatrixState.pAnyState.getRenderBox('target_rect');
    expect(box, isNotNull);
    expect(box!.size, tester.getSize(find.byType(_Probe)));
    expect(
      box.localToGlobal(Offset.zero),
      tester.getTopLeft(find.byType(_Probe)),
    );
  });
}
