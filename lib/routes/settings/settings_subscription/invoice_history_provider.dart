import 'package:flutter/material.dart';

import 'package:fluffychat/features/subscription/repo_v2/invoice_history_repo.dart';
import 'package:fluffychat/features/subscription/repo_v2/invoice_history_request.dart';
import 'package:fluffychat/features/subscription/repo_v2/invoice_history_response.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';

typedef _InvoiceLoader = ValueNotifier<AsyncState<List<Invoice>>>;

class InvoiceHistoryProvider extends StatefulWidget {
  final Widget Function(BuildContext, AsyncState<List<Invoice>>) builder;
  const InvoiceHistoryProvider({super.key, required this.builder});

  @override
  InvoiceHistoryProviderState createState() => InvoiceHistoryProviderState();
}

class InvoiceHistoryProviderState extends State<InvoiceHistoryProvider> {
  final _loader = _InvoiceLoader(AsyncLoading());

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _loader.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    _loader.value = AsyncLoading();
    final result = await InvoiceHistoryRepo.instance.get(
      InvoiceHistoryRequest(userID: Matrix.of(context).client.userID!),
    );
    final response = result.result;

    if (mounted) {
      _loader.value = response != null
          ? AsyncLoaded(response.invoices)
          : AsyncError(result.error ?? "Failed to fetch invoice history");
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: _loader,
    builder: (context, state, _) => widget.builder(context, state),
  );
}
