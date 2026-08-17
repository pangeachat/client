import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/analytics_data/analytics_data_service.dart';
import 'package:fluffychat/features/analytics_data/widgets/analytics_future_builder.dart';

/// The memo half of AnalyticsFutureBuilder: a rebuild with the same
/// dependencies must not re-run the fetch; a dependency change must.
void main() {
  testWidgets('re-issues the fetch only when dependencies change', (
    tester,
  ) async {
    var calls = 0;
    var deps = <Object?>['casa', 'es'];
    late StateSetter rebuild;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return MemoizedFutureBuilder<int>(
              dependencies: deps,
              fetch: () async => ++calls,
              builder: (context, snapshot) =>
                  Text('${snapshot.data ?? 'loading'}'),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('1'), findsOneWidget);

    // Same dependencies (a fresh but equal list): no new fetch.
    deps = <Object?>['casa', 'es'];
    rebuild(() {});
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('1'), findsOneWidget);

    // Two more no-op rebuilds.
    rebuild(() {});
    rebuild(() {});
    await tester.pumpAndSettle();
    expect(calls, 1);

    // A dependency changed: fetch again.
    deps = <Object?>['perro', 'es'];
    rebuild(() {});
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('2'), findsOneWidget);

    // A trailing "stream tick" key: fixed shape, replaced object → refetch;
    // the same object again → no refetch.
    final tick1 = Object();
    deps = <Object?>['perro', 'es', tick1];
    rebuild(() {});
    await tester.pumpAndSettle();
    expect(calls, 3);
    deps = <Object?>['perro', 'es', tick1];
    rebuild(() {});
    await tester.pumpAndSettle();
    expect(calls, 3);
    deps = <Object?>['perro', 'es', Object()];
    rebuild(() {});
    await tester.pumpAndSettle();
    expect(calls, 4);
  });

  testWidgets('AnalyticsFutureBuilder re-fetches once per construct-stream '
      'update and not on plain rebuilds', (tester) async {
    final updates = StreamController<AnalyticsStreamUpdate>.broadcast();
    addTearDown(updates.close);
    var calls = 0;
    late StateSetter rebuild;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return AnalyticsFutureBuilder<int>(
              stream: updates.stream,
              dependencies: const ['casa', 'es'],
              fetch: () async => ++calls,
              builder: (context, snapshot) =>
                  Text('${snapshot.data ?? 'loading'}'),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, 1);

    rebuild(() {});
    rebuild(() {});
    await tester.pumpAndSettle();
    expect(calls, 1);

    updates.add(AnalyticsStreamUpdate(points: 5));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('2'), findsOneWidget);

    // A rebuild between ticks reuses the tick's future.
    rebuild(() {});
    await tester.pumpAndSettle();
    expect(calls, 2);

    updates.add(AnalyticsStreamUpdate());
    await tester.pumpAndSettle();
    expect(calls, 3);
  });
}
