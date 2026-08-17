import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:fluffychat/features/analytics_data/analytics_data_service.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// A [FutureBuilder] over an analytics read that is issued **once per
/// construct-stream update or dependency change**, not once per rebuild.
///
/// The naive `FutureBuilder(future: service.getX(...))` inside `build()`
/// re-runs the read (box reads + deserialization) on every rebuild and flashes
/// the loading state each time. This widget keeps the doc's contract
/// (analytics-system.instructions.md, "Key Contracts": subscribe to the
/// construct stream during build) by wrapping a [StreamBuilder] on
/// [AnalyticsUpdateDispatcher.constructUpdateStream], and re-runs [fetch] only
/// when that stream emits or when [dependencies] change (compared with
/// [listEquals], so pass value-equal things: identifiers, language codes).
class AnalyticsFutureBuilder<T> extends StatelessWidget {
  final List<Object?> dependencies;
  final Future<T> Function() fetch;
  final AsyncWidgetBuilder<T> builder;

  const AnalyticsFutureBuilder({
    super.key,
    required this.dependencies,
    required this.fetch,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    final service = Matrix.of(context).analyticsDataService;
    return StreamBuilder<AnalyticsStreamUpdate>(
      stream: service.updateDispatcher.constructUpdateStream.stream,
      builder: (context, snapshot) => MemoizedFutureBuilder<T>(
        // A new AnalyticsStreamUpdate object per emission; the same object
        // across plain rebuilds — so it is a clean "stream ticked" key.
        dependencies: [...dependencies, snapshot.data],
        fetch: fetch,
        builder: builder,
      ),
    );
  }
}

/// The memo half of [AnalyticsFutureBuilder], without the stream: runs
/// [fetch] on first build and again only when [dependencies] change.
@visibleForTesting
class MemoizedFutureBuilder<T> extends StatefulWidget {
  final List<Object?> dependencies;
  final Future<T> Function() fetch;
  final AsyncWidgetBuilder<T> builder;

  const MemoizedFutureBuilder({
    super.key,
    required this.dependencies,
    required this.fetch,
    required this.builder,
  });

  @override
  State<MemoizedFutureBuilder<T>> createState() =>
      _MemoizedFutureBuilderState<T>();
}

class _MemoizedFutureBuilderState<T> extends State<MemoizedFutureBuilder<T>> {
  late Future<T> _future;
  late List<Object?> _dependencies;

  @override
  void initState() {
    super.initState();
    _dependencies = List.of(widget.dependencies);
    _future = widget.fetch();
  }

  @override
  void didUpdateWidget(covariant MemoizedFutureBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(widget.dependencies, _dependencies)) {
      _dependencies = List.of(widget.dependencies);
      _future = widget.fetch();
    }
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<T>(future: _future, builder: widget.builder);
}
