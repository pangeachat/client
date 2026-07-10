import 'package:collection/collection.dart';

import 'package:fluffychat/features/navigation/token_fields.dart';
import 'package:fluffychat/features/navigation/token_params/token_param.dart';

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

  // used by browse and own add course subpages to set initial language filter
  // and to maintain language filters across navigation
  final String? initialLanguageFilter;

  // public browsing options
  final String? previewRoomId;

  // new course options
  final String? createCourseId;
  final bool showNewCourseInvitePage;

  // private join options
  final String? privateCourseJoinCode;

  const AddCoursePageTokenParam({
    required this.subpage,
    this.initialLanguageFilter,
    this.previewRoomId,
    this.createCourseId,
    this.privateCourseJoinCode,
    this.showNewCourseInvitePage = false,
  });

  @override
  String build() {
    final subpage = this.subpage;
    final previewRoomId = this.previewRoomId;
    final createCourseId = this.createCourseId;
    final initialLanguageFilter = this.initialLanguageFilter;
    final privateCourseJoinCode = this.privateCourseJoinCode;

    final encodedSubpage = TokenFields.encode(subpage.name);
    switch (subpage) {
      case AddCourseSubpageEnum.browse:
        return previewRoomId != null && previewRoomId.isNotEmpty
            ? '$encodedSubpage/${TokenFields.encode(previewRoomId)}'
            : encodedSubpage;
      case AddCourseSubpageEnum.private:
        return TokenFields.join([
          encodedSubpage,
          if (privateCourseJoinCode != null && privateCourseJoinCode.isNotEmpty)
            'j${TokenFields.encode(privateCourseJoinCode)}',
        ]);
      case AddCourseSubpageEnum.own:
        if (createCourseId != null) {
          final encodedCourseId = TokenFields.encode(createCourseId);
          if (showNewCourseInvitePage) {
            return '$encodedSubpage/$encodedCourseId/invite';
          }
          return '$encodedSubpage/$encodedCourseId';
        }
        return TokenFields.join([
          encodedSubpage,
          if (initialLanguageFilter != null && initialLanguageFilter.isNotEmpty)
            'l${TokenFields.encode(initialLanguageFilter)}',
        ]);
    }
  }

  factory AddCoursePageTokenParam.parse(String param) {
    final parts = param.split('/');
    final chunks = TokenFields.split(parts.first);
    final subpage = AddCourseSubpageEnum.fromString(
      TokenFields.decode(chunks.first),
    );

    switch (subpage) {
      case AddCourseSubpageEnum.browse:
        if (parts.length > 1) {
          final previewRoomId = TokenFields.decode(parts[1]);
          return AddCoursePageTokenParam(
            subpage: subpage,
            previewRoomId: previewRoomId,
          );
        }
        return AddCoursePageTokenParam(subpage: subpage);
      case AddCourseSubpageEnum.private:
        final privateCourseJoinCode = chunks
            .skip(1)
            .firstWhereOrNull((c) => c.startsWith('j'))
            ?.substring(1);

        return AddCoursePageTokenParam(
          subpage: subpage,
          privateCourseJoinCode:
              privateCourseJoinCode != null && privateCourseJoinCode.isNotEmpty
              ? TokenFields.decode(privateCourseJoinCode)
              : null,
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
          final createCourseId = TokenFields.decode(parts[1]);
          return AddCoursePageTokenParam(
            subpage: subpage,
            createCourseId: createCourseId,
          );
        }

        final initialLanguageFilter = chunks
            .skip(1)
            .firstWhereOrNull((c) => c.startsWith('l'))
            ?.substring(1);

        return AddCoursePageTokenParam(
          subpage: subpage,
          initialLanguageFilter:
              initialLanguageFilter != null && initialLanguageFilter.isNotEmpty
              ? TokenFields.decode(initialLanguageFilter)
              : null,
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
      other.privateCourseJoinCode == privateCourseJoinCode &&
      other.showNewCourseInvitePage == showNewCourseInvitePage;

  @override
  int get hashCode => Object.hash(
    subpage,
    previewRoomId,
    createCourseId,
    initialLanguageFilter,
    privateCourseJoinCode,
    showNewCourseInvitePage,
  );
}
