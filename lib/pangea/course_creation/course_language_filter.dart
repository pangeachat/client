import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/course_creation/course_plan_filter_widget.dart';
import 'package:fluffychat/pangea/languages/language_display_name_widget.dart';
import 'package:fluffychat/pangea/languages/language_model.dart';
import 'package:fluffychat/widgets/matrix.dart';

class CourseLanguageFilter extends StatelessWidget {
  final LanguageModel? value;
  final void Function(LanguageModel?) onChanged;

  const CourseLanguageFilter({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final langs =
        MatrixState.pangeaController.pLanguageStore.unlocalizedTargetOptions;
    return CoursePlanFilter<LanguageModel>(
      value: value != null && langs.contains(value) ? value : null,
      onChanged: onChanged,
      items: langs,
      displayname: (v) => Row(
        children: [
          LanguageDisplayNameWidget(
            v,
            style: DefaultTextStyle.of(context).style,
            iconSize: 18.0,
            spacing: 6.0,
          ),
        ],
      ),
      enableSearch: true,
      defaultName: L10n.of(context).allLanguages,
      searchMatchFn: (item, searchValue) =>
          LanguageModel.search(item.value, searchValue, context),
    );
  }
}
