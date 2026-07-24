import 'package:fluffychat/features/navigation/panel_types_enum.dart';
import 'package:fluffychat/features/navigation/token_params/activity_token.dart';
import 'package:fluffychat/features/navigation/token_params/add_course_token.dart';
import 'package:fluffychat/features/navigation/token_params/analytics_practice_token.dart';
import 'package:fluffychat/features/navigation/token_params/analytics_token.dart';
import 'package:fluffychat/features/navigation/token_params/course_details_token.dart';
import 'package:fluffychat/features/navigation/token_params/grammar_analytics_token.dart';
import 'package:fluffychat/features/navigation/token_params/room_subpage_token.dart';
import 'package:fluffychat/features/navigation/token_params/room_token.dart';
import 'package:fluffychat/features/navigation/token_params/settings_token.dart';
import 'package:fluffychat/features/navigation/token_params/token_param.dart';
import 'package:fluffychat/features/navigation/token_params/vocab_analytics_token.dart';

/// One open-panel token from a workspace URL list (`left=` / `right=`).
///
/// [type] selects a `PanelDef` in `panel_registry.dart`; [param] is its
/// already-decoded argument (a room localpart, an analytics tab, an encoded
/// construct). See `routing.instructions.md`.
sealed class PanelToken<T extends TokenParam> {
  final PanelTypesEnum type;
  final T? param;

  const PanelToken(this.type, [this.param]);

  static final RegExp _typePattern = RegExp(r'^[a-z][a-z-]*$');

  static bool _validType(String s) => _typePattern.hasMatch(s);

  /// Parse one URL list element. It arrives still percent-encoded and already
  /// split out of the comma list. The first `:` splits type from param, so a
  /// room localpart (`!abc`) or an encoded construct survives; the param is
  /// decoded only after that split. Returns null for a malformed type, or for a
  /// hand-edited/truncated `%` escape that would make `Uri.decodeComponent`
  /// throw — the bad token is skipped rather than aborting the whole route.
  static PanelToken? parse(String encodedElement) {
    if (encodedElement.isEmpty) return null;
    final i = encodedElement.indexOf(':');
    if (i < 0) {
      final type = PanelTypesEnum.fromString(encodedElement);
      return _validType(encodedElement) && type != null ? _byType(type) : null;
    }
    final type = encodedElement.substring(0, i);
    final parsedType = PanelTypesEnum.fromString(type);
    if (!_validType(type) || parsedType == null) return null;
    final String param;
    try {
      param = Uri.decodeComponent(encodedElement.substring(i + 1));
    } catch (_) {
      // Truncated/invalid `%` escape (ArgumentError or FormatException): skip
      // this token rather than aborting the whole route parse.
      return null;
    }

    try {
      return _byType(parsedType, param);
    } catch (e) {
      // A parse method (TokenFields.decode, enum fromRoute, etc.) threw on
      // malformed input — skip this token rather than aborting route parse.
      return null;
    }
  }

  PanelToken? get popped => null;

  String get screenName {
    final param = this.param;
    if (param == null || param.build().isEmpty) return type.name;
    return '${type.name}:${param.build()}';
  }

  static PanelToken? _byType(PanelTypesEnum type, [String? param]) {
    if (type.requireParam && (param == null || param.isEmpty)) {
      return null;
    }

    try {
      final PanelToken? token = switch (type) {
        PanelTypesEnum.chats => ChatsPanelToken(),
        PanelTypesEnum.room => RoomPanelToken(RoomTokenParam.parse(param!)),
        PanelTypesEnum.session => SessionPanelToken(
          RoomTokenParam.parse(param!),
        ),
        PanelTypesEnum.archivedroom => ArchivedRoomPanelToken(
          RoomTokenParam.parse(param!),
        ),
        PanelTypesEnum.activity => ActivityPanelToken(
          ActivityTokenParam.parse(param!),
        ),
        PanelTypesEnum.course => CoursePanelToken(
          param != null ? CourseDetailsTokenParam.parse(param) : null,
        ),
        PanelTypesEnum.coursepage => CoursePagePanelToken(
          RoomSubpageTokenParam.parse(param!),
        ),
        PanelTypesEnum.addcourse => AddCoursePanelToken(),
        PanelTypesEnum.addcoursepage => AddCoursePagePanelToken(
          AddCoursePageTokenParam.parse(param!),
        ),
        PanelTypesEnum.settings => SettingsPanelToken(),
        PanelTypesEnum.settingspage => SettingsPagePanelToken(
          SettingsTokenParam.parse(param!),
        ),
        PanelTypesEnum.analytics => AnalyticsPanelToken(
          AnalyticsTokenParam.parse(param!),
        ),
        PanelTypesEnum.vocab => VocabAnalyticsPanelToken(
          VocabAnalyticsTokenParam.parse(param!),
        ),
        PanelTypesEnum.grammar => GrammarAnalyticsPanelToken(
          GrammarAnalyticsTokenParam.parse(param!),
        ),
        PanelTypesEnum.review => ReviewPanelToken(),
        PanelTypesEnum.practice => AnalyticsPracticePanelToken(
          AnalyticsPracticeTokenParam.parse(param!),
        ),
        PanelTypesEnum.newprivatechat => NewPrivateChatPanelToken(),
        PanelTypesEnum.archive => ArchivePanelToken(),
      };
      return token;
    } catch (e) {
      return null;
    }
  }

  /// Encode for a URL list. The param is percent-encoded so its own commas and
  /// colons can't be mistaken for list or field delimiters.
  String encode() => param == null
      ? type.name
      : '${type.name}:${Uri.encodeComponent(param!.build())}';

  @override
  bool operator ==(Object other) =>
      other is PanelToken && other.type == type && other.param == param;

  @override
  int get hashCode => Object.hash(type, param);

  @override
  String toString() => encode();
}

class ChatsPanelToken extends PanelToken {
  const ChatsPanelToken() : super(PanelTypesEnum.chats);
}

class ActivityPanelToken extends PanelToken<ActivityTokenParam> {
  const ActivityPanelToken(ActivityTokenParam param)
    : super(PanelTypesEnum.activity, param);

  @override
  String get screenName => type.name;
}

class CoursePanelToken extends PanelToken<CourseDetailsTokenParam> {
  const CoursePanelToken([CourseDetailsTokenParam? param])
    : super(PanelTypesEnum.course, param);
}

class CoursePagePanelToken extends PanelToken<RoomSubpageTokenParam> {
  const CoursePagePanelToken(RoomSubpageTokenParam param)
    : super(PanelTypesEnum.coursepage, param);

  @override
  CoursePagePanelToken? get popped {
    final param = this.param;
    if (param == null || !param.isPushed) return null;
    final poppedParam = param.poppedParam;
    if (poppedParam == null) return null;
    return CoursePagePanelToken(poppedParam);
  }
}

class AddCoursePanelToken extends PanelToken {
  const AddCoursePanelToken() : super(PanelTypesEnum.addcourse);
}

class AddCoursePagePanelToken extends PanelToken<AddCoursePageTokenParam> {
  const AddCoursePagePanelToken(AddCoursePageTokenParam param)
    : super(PanelTypesEnum.addcoursepage, param);

  @override
  String get screenName {
    final param = this.param;
    if (param is! AddCoursePageTokenParam) return type.name;
    // Identity (course id, room id, join code) and filters stay out of the
    // name; only the subpage and the pushed leaf are navigational.
    final leaf = switch (param.subpage) {
      AddCourseSubpageEnum.browse =>
        param.previewRoomId != null ? 'browse/preview' : 'browse',
      AddCourseSubpageEnum.private => 'private',
      AddCourseSubpageEnum.own =>
        param.createCourseId == null
            ? 'own'
            : param.showNewCourseInvitePage
            ? 'own/invite'
            : 'own/preview',
    };
    return '${type.name}:$leaf';
  }

  @override
  AddCoursePagePanelToken? get popped {
    final param = this.param;
    if (param == null || !param.isPushed) return null;
    final poppedParam = param.poppedParam;
    if (poppedParam == null) return null;
    return AddCoursePagePanelToken(poppedParam);
  }
}

class SettingsPanelToken extends PanelToken {
  const SettingsPanelToken() : super(PanelTypesEnum.settings);
}

class SettingsPagePanelToken extends PanelToken<SettingsTokenParam> {
  const SettingsPagePanelToken(SettingsTokenParam param)
    : super(PanelTypesEnum.settingspage, param);

  @override
  SettingsPagePanelToken? get popped {
    final param = this.param;
    if (param == null || !param.isPushed) return null;
    final poppedParam = param.poppedParam;
    if (poppedParam == null) return null;
    return SettingsPagePanelToken(poppedParam);
  }
}

class AnalyticsPanelToken extends PanelToken<AnalyticsTokenParam> {
  const AnalyticsPanelToken(AnalyticsTokenParam param)
    : super(PanelTypesEnum.analytics, param);
}

class VocabAnalyticsPanelToken extends PanelToken<VocabAnalyticsTokenParam> {
  const VocabAnalyticsPanelToken(VocabAnalyticsTokenParam param)
    : super(PanelTypesEnum.vocab, param);

  @override
  String get screenName => type.name;
}

class GrammarAnalyticsPanelToken
    extends PanelToken<GrammarAnalyticsTokenParam> {
  const GrammarAnalyticsPanelToken(GrammarAnalyticsTokenParam param)
    : super(PanelTypesEnum.grammar, param);

  @override
  String get screenName => type.name;
}

class ReviewPanelToken extends PanelToken {
  const ReviewPanelToken() : super(PanelTypesEnum.review);
}

class AnalyticsPracticePanelToken
    extends PanelToken<AnalyticsPracticeTokenParam> {
  const AnalyticsPracticePanelToken(AnalyticsPracticeTokenParam param)
    : super(PanelTypesEnum.practice, param);
}

class NewPrivateChatPanelToken extends PanelToken {
  const NewPrivateChatPanelToken() : super(PanelTypesEnum.newprivatechat);
}

class ArchivePanelToken extends PanelToken {
  const ArchivePanelToken() : super(PanelTypesEnum.archive);
}

class RoomPanelToken extends _ChatViewPanelToken {
  const RoomPanelToken(super.param) : super(type: PanelTypesEnum.room);

  @override
  RoomPanelToken createPoppedToken(RoomTokenParam poppedParam) =>
      RoomPanelToken(poppedParam);
}

class SessionPanelToken extends _ChatViewPanelToken {
  const SessionPanelToken(super.param) : super(type: PanelTypesEnum.session);

  @override
  SessionPanelToken createPoppedToken(RoomTokenParam poppedParam) =>
      SessionPanelToken(poppedParam);
}

class ArchivedRoomPanelToken extends _ChatViewPanelToken {
  const ArchivedRoomPanelToken(super.param)
    : super(type: PanelTypesEnum.archivedroom);

  @override
  ArchivedRoomPanelToken createPoppedToken(RoomTokenParam poppedParam) =>
      ArchivedRoomPanelToken(poppedParam);
}

abstract class _ChatViewPanelToken extends PanelToken<RoomTokenParam> {
  const _ChatViewPanelToken(
    RoomTokenParam param, {
    required PanelTypesEnum type,
  }) : super(type, param);

  _ChatViewPanelToken createPoppedToken(RoomTokenParam poppedParam);

  @override
  _ChatViewPanelToken? get popped {
    final param = this.param;
    if (param == null || !param.isPushed) return null;
    final poppedParam = param.poppedParam;
    if (poppedParam == null) return null;
    return createPoppedToken(poppedParam);
  }

  @override
  String get screenName {
    final param = this.param;
    if (param is! RoomTokenParam) return type.name;
    if (param.subpage == null || param.subpage!.isEmpty) return type.name;

    final filter = param.filter;
    final sub = filter == null ? param.subpage! : '${param.subpage}/$filter';
    return '${type.name}:$sub';
  }
}
