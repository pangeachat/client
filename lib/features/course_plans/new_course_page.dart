import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/features/course_plans/courses/course_plan_model.dart';
import 'package:fluffychat/features/languages/p_language_store.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/courses/course_search_view.dart';
import 'package:fluffychat/routes/courses/new_course_search_controller.dart';
import 'package:fluffychat/widgets/matrix.dart';

class NewCoursePage extends StatefulWidget {
  final String? spaceId;
  final String? initialLanguageCode;
  final bool showAll;

  /// world_v2: when this page is the change-course step hosted inside an
  /// existing course panel (a `course:addcourse` push, `spaceId != null`), the
  /// panel supplies its leading `←` back to the card — the route-driven
  /// add-to-space context otherwise has no back. See `routing.instructions.md`.
  final Widget closeButton;

  const NewCoursePage({
    super.key,
    this.spaceId,
    this.initialLanguageCode,
    this.showAll = false,
    required this.closeButton,
  });

  @override
  State<NewCoursePage> createState() => NewCoursePageState();
}

class NewCoursePageState extends State<NewCoursePage> {
  late final NewCourseSearchController _controller = NewCourseSearchController(
    client: Matrix.of(context).client,
    spaceId: widget.spaceId,
  );

  @override
  void initState() {
    super.initState();

    if (!widget.showAll) {
      final fromInitialCode = widget.initialLanguageCode != null
          ? PLanguageStore.byLangCode(widget.initialLanguageCode!)
          : null;
      final userL2 = MatrixState.pangeaController.userController.userL2;
      _controller.targetLanguageFilter.value = fromInitialCode ?? userL2;
    }

    _controller.initCourseSearch();
  }

  @override
  void dispose() {
    _controller.disposeCourseSearch();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spaceId = widget.spaceId;
    return CourseSearchView<CoursePlanModel>(
      courseSearch: _controller,
      title: spaceId != null
          ? L10n.of(context).addCoursePlan
          : L10n.of(context).startOwn,
      actions: spaceId == null
          ? [
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: L10n.of(context).close,
                onPressed: () => context.go('/'),
              ),
            ]
          : null,
      labelText: L10n.of(context).searchCoursePlans,
      notFoundMessage: L10n.of(context).noCourseTemplatesFound,
      notFoundButtonLabel: L10n.of(context).continueText,
      closeButton: widget.closeButton,
    );
  }
}
