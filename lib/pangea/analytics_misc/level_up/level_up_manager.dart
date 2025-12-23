import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/analytics_data/analytics_data_service.dart';
import 'package:fluffychat/pangea/analytics_misc/client_analytics_extension.dart';
import 'package:fluffychat/pangea/analytics_misc/construct_type_enum.dart';
import 'package:fluffychat/pangea/analytics_misc/level_summary_extension.dart';
import 'package:fluffychat/pangea/languages/language_model.dart';
import 'package:fluffychat/widgets/matrix.dart';

class LevelUpManager {
  // Singleton instance so analytics can be generated when level up is initiated, and be ready by the time user clicks on banner
  static final LevelUpManager instance = LevelUpManager._internal();

  LevelUpManager._internal();

  int prevLevel = 0;
  int level = 0;

  int prevGrammar = 0;
  int nextGrammar = 0;
  int prevVocab = 0;
  int nextVocab = 0;

  bool hasSeenPopup = false;
  bool shouldAutoPopup = false;

  Future<void> preloadAnalytics(
    int level,
    int prevLevel,
    AnalyticsDataService analyticsService,
  ) async {
    this.level = level;
    this.prevLevel = prevLevel;

    //For on route change behavior, if added in the future
    shouldAutoPopup = true;

    nextGrammar = analyticsService.numConstructs(ConstructTypeEnum.morph);
    nextVocab = analyticsService.numConstructs(ConstructTypeEnum.vocab);

    final LanguageModel? l2 =
        MatrixState.pangeaController.userController.userL2;
    final Room? analyticsRoom =
        MatrixState.pangeaController.matrixState.client.analyticsRoomLocal(l2!);

    if (analyticsRoom != null) {
      final lastSummary = analyticsRoom.levelUpSummary;

      //Set grammar and vocab from last level summary, if there is one. Otherwise set to placeholder data
      if (lastSummary != null &&
          lastSummary.levelVocabConstructs != null &&
          lastSummary.levelGrammarConstructs != null) {
        prevVocab = lastSummary.levelVocabConstructs!;
        prevGrammar = lastSummary.levelGrammarConstructs!;
      } else {
        prevGrammar = nextGrammar - (nextGrammar / prevLevel).round();
        prevVocab = nextVocab - (nextVocab / prevLevel).round();
      }
    }
  }

  void markPopupSeen() {
    hasSeenPopup = true;
    shouldAutoPopup = false;
  }

  void reset() {
    hasSeenPopup = false;
    shouldAutoPopup = false;
    prevLevel = 0;
    level = 0;
    prevGrammar = 0;
    nextGrammar = 0;
    prevVocab = 0;
    nextVocab = 0;
  }
}
