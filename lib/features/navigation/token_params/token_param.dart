import 'package:fluffychat/features/navigation/panel_token.dart';
import 'package:fluffychat/features/navigation/token_params/activity_token.dart';
import 'package:fluffychat/features/navigation/token_params/add_course_token.dart';
import 'package:fluffychat/features/navigation/token_params/analytics_practice_token.dart';
import 'package:fluffychat/features/navigation/token_params/analytics_token.dart';
import 'package:fluffychat/features/navigation/token_params/course_details_subpage_token.dart';
import 'package:fluffychat/features/navigation/token_params/course_details_token.dart';
import 'package:fluffychat/features/navigation/token_params/grammar_analytics_token.dart';
import 'package:fluffychat/features/navigation/token_params/room_token.dart';
import 'package:fluffychat/features/navigation/token_params/settings_token.dart';
import 'package:fluffychat/features/navigation/token_params/vocab_analytics_token_param.dart';

abstract class TokenParam {
  final String type;
  const TokenParam(this.type);

  PanelToken get token => PanelToken(type, this);

  bool get isPushed => false;

  TokenParam? get poppedParam => null;

  String build();

  static TokenParam? byType(String type, String param) {
    return switch (type) {
      'chats' => null,
      'room' || 'session' => RoomTokenParam.parse(param),
      'addcourse' => AddCourseTokenParam.parse(param),
      'course' => CourseDetailsTokenParam.parse(param),
      'activity' => ActivityTokenParam.parse(param),
      'coursepage' => CourseDetailsSubpageTokenParam.parse(param),
      'analytics' => AnalyticsTokenParam.parse(param),
      'settings' => null,
      'settingspage' => SettingsTokenParam.parse(param),
      'vocab' => VocabAnalyticsTokenParam.parse(param),
      'grammar' => GrammarAnalyticsTokenParam.parse(param),
      'practice' => AnalyticsPracticeTokenParam.parse(param),
      _ => null,
    };
  }

  @override
  bool operator ==(Object other) => other is TokenParam && other.type == type;

  @override
  int get hashCode => type.hashCode;
}
