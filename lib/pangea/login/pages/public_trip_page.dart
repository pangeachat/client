import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/error_indicator.dart';
import 'package:fluffychat/pangea/course_creation/course_plan_filter_widget.dart';
import 'package:fluffychat/pangea/learning_settings/enums/language_level_type_enum.dart';
import 'package:fluffychat/pangea/learning_settings/models/language_model.dart';
import 'package:fluffychat/pangea/spaces/utils/public_course_extension.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';

class PublicTripPage extends StatefulWidget {
  const PublicTripPage({
    super.key,
  });

  @override
  State<PublicTripPage> createState() => PublicTripPageState();
}

class PublicTripPageState extends State<PublicTripPage> {
  bool loading = true;
  Object? error;

  LanguageLevelTypeEnum? languageLevelFilter;
  LanguageModel? instructionLanguageFilter;
  LanguageModel? targetLanguageFilter;

  List<PublicRoomsChunk> discoveredCourses = [];
  String? nextBatch;

  @override
  void initState() {
    super.initState();

    final target = MatrixState.pangeaController.languageController.userL2;
    if (target != null) {
      setTargetLanguageFilter(target);
    }

    final base = MatrixState.pangeaController.languageController.systemLanguage;
    if (base != null) {
      setInstructionLanguageFilter(base);
    }

    _loadCourses();
  }

  void setLanguageLevelFilter(LanguageLevelTypeEnum? level) {
    setState(() => languageLevelFilter = level);
  }

  void setInstructionLanguageFilter(LanguageModel? language) {
    setState(() => instructionLanguageFilter = language);
  }

  void setTargetLanguageFilter(LanguageModel? language) {
    setState(() => targetLanguageFilter = language);
  }

  List<PublicRoomsChunk> get filteredCourses {
    // TODO add filtering via course info
    return discoveredCourses;
  }

  Future<void> _loadCourses() async {
    try {
      setState(() {
        loading = true;
        error = null;
      });

      final resp = await Matrix.of(context).client.requestPublicCourses(
            since: nextBatch,
          );

      for (final room in resp.chunk) {
        if (!discoveredCourses.any((e) => e.roomId == room.roomId)) {
          discoveredCourses.add(room);
        }
      }

      nextBatch = resp.nextBatch;
    } catch (e) {
      error = e;
    } finally {
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          spacing: 10.0,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.map_outlined),
            Text(L10n.of(context).browsePublicTrips),
          ],
        ),
      ),
      body: SafeArea(
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(30.0),
            constraints: const BoxConstraints(
              maxWidth: 450,
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 8.0,
                        runSpacing: 8.0,
                        alignment: WrapAlignment.start,
                        children: [
                          CoursePlanFilter<LanguageModel>(
                            value: instructionLanguageFilter,
                            onChanged: setInstructionLanguageFilter,
                            items: MatrixState
                                .pangeaController.pLanguageStore.baseOptions,
                            displayname: (v) =>
                                v.getDisplayName(context) ?? v.displayName,
                            enableSearch: true,
                            defaultName:
                                L10n.of(context).languageOfInstructionsLabel,
                            shortName: L10n.of(context).allLanguages,
                          ),
                          CoursePlanFilter<LanguageModel>(
                            value: targetLanguageFilter,
                            onChanged: setTargetLanguageFilter,
                            items: MatrixState
                                .pangeaController.pLanguageStore.targetOptions,
                            displayname: (v) =>
                                v.getDisplayName(context) ?? v.displayName,
                            enableSearch: true,
                            defaultName: L10n.of(context).targetLanguageLabel,
                            shortName: L10n.of(context).allLanguages,
                          ),
                          CoursePlanFilter<LanguageLevelTypeEnum>(
                            value: languageLevelFilter,
                            onChanged: setLanguageLevelFilter,
                            items: LanguageLevelTypeEnum.values,
                            displayname: (v) => v.string,
                            defaultName: L10n.of(context).cefrLevelLabel,
                            shortName: L10n.of(context).allCefrLevels,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20.0),
                if (error != null)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: ErrorIndicator(
                        message: L10n.of(context).failedToLoadCourses,
                      ),
                    ),
                  )
                else if (!loading &&
                    filteredCourses.isEmpty &&
                    nextBatch == null)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Text(L10n.of(context).noCoursesFound),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.separated(
                      itemCount: filteredCourses.length + 1,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 10.0),
                      itemBuilder: (context, index) {
                        if (index == filteredCourses.length) {
                          return Center(
                            child: loading
                                ? const CircularProgressIndicator.adaptive()
                                : nextBatch != null
                                    ? TextButton(
                                        onPressed: _loadCourses,
                                        child: Text(L10n.of(context).loadMore),
                                      )
                                    : const SizedBox(),
                          );
                        }

                        final course = filteredCourses[index];
                        final displayname = course.name ??
                            course.canonicalAlias ??
                            L10n.of(context).emptyChat;
                        return ListTile(
                          title: Text(
                            displayname,
                          ),
                          leading: Avatar(
                            mxContent: course.avatarUrl,
                            name: displayname,
                            borderRadius: BorderRadius.circular(
                              AppConfig.borderRadius / 2,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
