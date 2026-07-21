import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/features/languages/p_language_store.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/spaces/public_course_extension.dart';
import 'package:fluffychat/routes/courses/course_search_view.dart';
import 'package:fluffychat/routes/courses/public_course_search_controller.dart';
import 'package:fluffychat/widgets/matrix.dart';

class FindCoursePage extends StatefulWidget {
  final Widget closeButton;
  final String? initialLanguageCode;
  final bool showAll;
  const FindCoursePage({
    super.key,
    required this.closeButton,
    this.initialLanguageCode,
    this.showAll = false,
  });

  @override
  State<FindCoursePage> createState() => FindCoursePageState();
}

class FindCoursePageState extends State<FindCoursePage> {
  late final _controller = PublicCourseSearchController(
    client: Matrix.of(context).client,
  );

  @override
  void initState() {
    super.initState();
    final availableLanguages =
        MatrixState.pangeaController.pLanguageStore.unlocalizedTargetOptions;

    final l2 = MatrixState.pangeaController.userController.userL2;
    final initialLangCode = widget.initialLanguageCode;
    final initialLang = initialLangCode != null
        ? PLanguageStore.byLangCode(initialLangCode)
        : null;

    final targetLang = (initialLang == null && widget.showAll)
        ? null
        : availableLanguages.contains(initialLang)
        ? initialLang
        : availableLanguages.contains(initialLang?.unlocalized)
        ? initialLang?.unlocalized
        : availableLanguages.contains(l2)
        ? l2
        : availableLanguages.contains(l2?.unlocalized)
        ? l2?.unlocalized
        : null;

    _controller.targetLanguageFilter.value = targetLang;
    _controller.initCourseSearch();
  }

  @override
  void dispose() {
    _controller.disposeCourseSearch();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CourseSearchView<PublicCoursesChunk>(
      courseSearch: _controller,
      title: L10n.of(context).browsePublicCourses,
      actions: [
        IconButton(
          icon: const Icon(Icons.close),
          tooltip: L10n.of(context).close,
          onPressed: () => context.go('/'),
        ),
      ],
      hintText: L10n.of(context).searchPublicCourses,
      notFoundMessage: L10n.of(context).noPublicCoursesFound,
      notFoundButtonLabel: L10n.of(context).startOwn,
      closeButton: widget.closeButton,
    );
  }
}
