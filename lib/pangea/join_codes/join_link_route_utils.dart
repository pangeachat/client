import 'package:go_router/go_router.dart';

import 'package:fluffychat/pangea/spaces/space_constants.dart';

String? resolveJoinClassCodeFromUri({
  required Uri uri,
  Map<String, String> pathParameters = const {},
}) {
  final queryCode = uri.queryParameters[SpaceConstants.classCode]?.trim();
  if (queryCode != null && queryCode.isNotEmpty) {
    return queryCode;
  }

  final pathCode = pathParameters['classCode']?.trim();
  if (pathCode == null || pathCode.isEmpty) {
    return null;
  }

  return pathCode;
}

String? resolveJoinClassCode(GoRouterState state) => resolveJoinClassCodeFromUri(
  uri: state.uri,
  pathParameters: state.pathParameters,
);
