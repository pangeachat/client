import 'package:flutter/material.dart';

import 'package:fluffychat/routes/world/user_cluster_view_model.dart';
import 'package:fluffychat/widgets/matrix.dart';

class UserClusterViewModelBuilder extends StatefulWidget {
  final Widget Function(BuildContext context, UserClusterViewModel viewModel)
  builder;
  const UserClusterViewModelBuilder({super.key, required this.builder});

  @override
  UserClusterViewModelBuilderState createState() =>
      UserClusterViewModelBuilderState();
}

class UserClusterViewModelBuilderState
    extends State<UserClusterViewModelBuilder> {
  late final UserClusterViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    final matrix = Matrix.of(context);
    _viewModel = WorldUserClusterViewModel(
      analyticsService: matrix.analyticsDataService,
      client: matrix.client,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _viewModel.reloadProfile();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _viewModel);
}
