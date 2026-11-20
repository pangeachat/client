import 'package:collection/collection.dart';

import 'package:fluffychat/features/navigation/room_id_url.dart';
import 'package:fluffychat/features/navigation/token_fields.dart';
import 'package:fluffychat/features/navigation/token_params/token_param.dart';
import 'package:fluffychat/pangea/spaces/course_access_filter.dart';

enum AddCourseSubpageEnum {
  own,
  browse,
  private;

  static AddCourseSubpageEnum fromString(String value) =>
      AddCourseSubpageEnum.values.firstWhereOrNull((v) => v.name == value) ??
      AddCourseSubpageEnum.browse;
}

class AddCoursePageTokenParam extends TokenParam {
  final AddCourseSubpageEnum subpage;

  // Used by browse and own add course subpages to set initial language
  // filter and to maintain language filters across navigation. String filter
  // supercedes boolean all languages flag
  final String? initialLanguageFilter;
  final bool allLanguagesFilter;

  // public browsing options
  final String? previewRoomId;

  // Carried like the language filter, so the browse list's access pill
  // survives opening a course preview and coming back.
  final CourseAccessFilter accessFilter;

  // new course options
  final String? createCourseId;
  final bool showNewCourseInvitePage;

  // private join options
  final String? privateCourseJoinCode;

  const AddCoursePageTokenParam({
    required this.subpage,
    this.initialLanguageFilter,
    this.allLanguagesFilter = false,
    this.previewRoomId,
    this.accessFilter = CourseAccessFilter.all,
    this.createCourseId,
    this.privateCourseJoinCode,
    this.showNewCourseInvitePage = false,
  });

  @override
  bool get isPushed {
    switch (subpage) {
      case AddCourseSubpageEnum.browse:
        return previewRoomId != null;
      case AddCourseSubpageEnum.private:
        return false;
      case AddCourseSubpageEnum.own:
        return createCourseId != null;
    }
  }

  /// The single-course PREVIEW state of the browse / start-my-own flows
  /// (#7826): the sheet rests low and the map scopes to the course's
  /// activities. The own-flow's invite step is excluded — a form, not a
  /// preview.
  bool get isCoursePreview {
    switch (subpage) {
      case AddCourseSubpageEnum.browse:
        return previewRoomId != null;
      case AddCourseSubpageEnum.private:
        return false;
      case AddCourseSubpageEnum.own:
        return createCourseId != null && !showNewCourseInvitePage;
    }
  }

  /// The start-my-own preview, which carries the course settings rows above
  /// Create course and so rests taller than a browse preview.
  bool get isCreateCoursePreview =>
      subpage == AddCourseSubpageEnum.own && isCoursePreview;

  @override
  AddCoursePageTokenParam? get poppedParam {
    switch (subpage) {
      case AddCourseSubpageEnum.browse:
        if (previewRoomId == null) return null;
        return AddCoursePageTokenParam(
          subpage: subpage,
          initialLanguageFilter: initialLanguageFilter,
          allLanguagesFilter: allLanguagesFilter,
          accessFilter: accessFilter,
        );
      case AddCourseSubpageEnum.private:
        return null;
      case AddCourseSubpageEnum.own:
        if (createCourseId == null) return null;
        if (showNewCourseInvitePage) {
          return AddCoursePageTokenParam(
            subpage: subpage,
            createCourseId: createCourseId,
            initialLanguageFilter: initialLanguageFilter,
            allLanguagesFilter: allLanguagesFilter,
          );
        }
        return AddCoursePageTokenParam(
          subpage: subpage,
          initialLanguageFilter: initialLanguageFilter,
          allLanguagesFilter: allLanguagesFilter,
        );
    }
  }

  @override
  String build() {
    final subpage = this.subpage;
    final previewRoomId = this.previewRoomId;
    final createCourseId = this.createCourseId;
    final initialLanguageFilter = this.initialLanguageFilter;
    final privateCourseJoinCode = this.privateCourseJoinCode;

    final encodedSubpage = TokenFields.encode(subpage.name);

    final encodedLanguage =
        initialLanguageFilter != null && initialLanguageFilter.isNotEmpty
        ? 'l${TokenFields.encode(initialLanguageFilter)}'
        : null;

    final encodedJoinCode =
        privateCourseJoinCode != null && privateCourseJoinCode.isNotEmpty
        ? "j${TokenFields.encode(privateCourseJoinCode)}"
        : null;

    final encodedAllLanguagesFilter = allLanguagesFilter ? 'a' : null;

    final encodedAccessFilter = accessFilter != CourseAccessFilter.all
        ? 'r${accessFilter.name}'
        : null;

    switch (subpage) {
      case AddCourseSubpageEnum.browse:
        final encodedPreviewRoomId =
            previewRoomId != null && previewRoomId.isNotEmpty
            ? TokenFields.encode(shortRoomId(previewRoomId))
            : null;

        final route = encodedPreviewRoomId != null
            ? '$encodedSubpage/$encodedPreviewRoomId'
            : encodedSubpage;

        return TokenFields.join([
          route,
          ?encodedLanguage,
          ?encodedAllLanguagesFilter,
          ?encodedAccessFilter,
        ]);
      case AddCourseSubpageEnum.private:
        return TokenFields.join([encodedSubpage, ?encodedJoinCode]);
      case AddCourseSubpageEnum.own:
        if (createCourseId != null) {
          final encodedCourseId = TokenFields.encode(createCourseId);
          if (showNewCourseInvitePage) {
            return '$encodedSubpage/$encodedCourseId/invite';
          }
          return TokenFields.join([
            '$encodedSubpage/$encodedCourseId',
            ?encodedLanguage,
            ?encodedAllLanguagesFilter,
          ]);
        }
        return TokenFields.join([
          encodedSubpage,
          ?encodedLanguage,
          ?encodedAllLanguagesFilter,
        ]);
    }
  }

  factory AddCoursePageTokenParam.parse(String param) {
    final parts = param.split('/');
    final routeChunks = TokenFields.split(parts.first);
    final subpage = AddCourseSubpageEnum.fromString(
      TokenFields.decode(routeChunks.first),
    );

    final paramChunks = TokenFields.split(parts.last);
    final params = paramChunks.skip(1);

    final encodedLanguageEntry = params
        .firstWhereOrNull((p) => p.startsWith('l'))
        ?.substring(1);

    final languageFilter =
        encodedLanguageEntry != null && encodedLanguageEntry.isNotEmpty
        ? TokenFields.decode(encodedLanguageEntry)
        : null;

    final encodedJoinCodeEntry = params
        .firstWhereOrNull((p) => p.startsWith('j'))
        ?.substring(1);

    final joinCode =
        encodedJoinCodeEntry != null && encodedJoinCodeEntry.isNotEmpty
        ? TokenFields.decode(encodedJoinCodeEntry)
        : null;

    final allLanguagesFilter = params.any((p) => p == 'a');

    final encodedAccessFilterEntry = params
        .firstWhereOrNull((p) => p.startsWith('r'))
        ?.substring(1);

    // A hand-edited, unknown filter name opens the list unfiltered, as an
    // undecodable language field opens it on the raw field.
    final accessFilter =
        (encodedAccessFilterEntry != null
            ? CourseAccessFilter.fromName(encodedAccessFilterEntry)
            : null) ??
        CourseAccessFilter.all;

    switch (subpage) {
      case AddCourseSubpageEnum.browse:
        if (parts.length > 1) {
          final roomIdChunks = TokenFields.split(parts[1]);
          final previewRoomId = TokenFields.decode(roomIdChunks.first);
          return AddCoursePageTokenParam(
            subpage: subpage,
            previewRoomId: previewRoomId,
            initialLanguageFilter: languageFilter,
            allLanguagesFilter: allLanguagesFilter,
            accessFilter: accessFilter,
          );
        }

        return AddCoursePageTokenParam(
          subpage: subpage,
          initialLanguageFilter: languageFilter,
          allLanguagesFilter: allLanguagesFilter,
          accessFilter: accessFilter,
        );
      case AddCourseSubpageEnum.private:
        return AddCoursePageTokenParam(
          subpage: subpage,
          privateCourseJoinCode: joinCode,
        );
      case AddCourseSubpageEnum.own:
        if (parts.length > 2 && parts[2] == 'invite') {
          final createCourseId = TokenFields.decode(parts[1]);
          return AddCoursePageTokenParam(
            subpage: subpage,
            createCourseId: createCourseId,
            showNewCourseInvitePage: true,
          );
        }

        if (parts.length > 1) {
          final courseIdChunks = TokenFields.split(parts[1]);
          final createCourseId = TokenFields.decode(courseIdChunks.first);
          return AddCoursePageTokenParam(
            subpage: subpage,
            createCourseId: createCourseId,
            initialLanguageFilter: languageFilter,
            allLanguagesFilter: allLanguagesFilter,
          );
        }

        return AddCoursePageTokenParam(
          subpage: subpage,
          initialLanguageFilter: languageFilter,
          allLanguagesFilter: allLanguagesFilter,
        );
    }
  }

  @override
  bool operator ==(Object other) =>
      other is AddCoursePageTokenParam &&
      other.subpage == subpage &&
      other.previewRoomId == previewRoomId &&
      other.createCourseId == createCourseId &&
      other.initialLanguageFilter == initialLanguageFilter &&
      other.accessFilter == accessFilter &&
      other.privateCourseJoinCode == privateCourseJoinCode &&
      other.showNewCourseInvitePage == showNewCourseInvitePage;

  @override
  int get hashCode => Object.hash(
    subpage,
    previewRoomId,
    createCourseId,
    initialLanguageFilter,
    accessFilter,
    privateCourseJoinCode,
    showNewCourseInvitePage,
  );
}
