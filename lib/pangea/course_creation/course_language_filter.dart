import 'package:flutter/material.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/course_creation/course_plan_filter_widget.dart';
import 'package:fluffychat/pangea/languages/language_display_name_postfix_widget.dart';
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
    final l10n = L10n.of(context);
    return CoursePlanFilter<LanguageModel>(
      value: value != null && langs.contains(value) ? value : null,
      onChanged: onChanged,
      items: langs,
      displayname: (v) => Row(
        children: [
          LanguageDisplayNamePostfixWidget(
            v,
            style: DefaultTextStyle.of(context).style,
            iconSize: 18.0,
            spacing: 6.0,
          ),
        ],
      ),
      selectedItemBuilder: (v) => Row(
        children: [
          Text(
            v.getDisplayName(l10n),
            style: DefaultTextStyle.of(context).style,
          ),
        ],
      ),
      enableSearch: true,
      defaultName: l10n.allLanguages,
      searchMatchFn: (item, searchValue) =>
          LanguageModel.search(item.value, searchValue, context),
    );
  }
}
