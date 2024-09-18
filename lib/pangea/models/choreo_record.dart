import 'dart:convert';

import 'package:fluffychat/pangea/enum/construct_type_enum.dart';
import 'package:fluffychat/pangea/enum/construct_use_type_enum.dart';
import 'package:fluffychat/pangea/models/analytics/constructs_model.dart';
import 'package:fluffychat/pangea/models/pangea_match_model.dart';
import 'package:matrix/matrix.dart';

import 'it_step.dart';

/// this class lives within a [PangeaIGCEvent]
/// it always has a [RepresentationEvent] parent
/// These live as separate event so that anyone can add and edit grammar checks
/// to a representation
/// It represents the real-time changes to a text
/// TODO - start saving senderL2Code in choreoRecord to be able better decide the useType

class ChoreoRecord {
  /// ordered versions of the representation, with first being original and last
  /// being the final sent text
  /// there is not a 1-to-1 map from steps to matches
  List<ChoreoRecordStep> choreoSteps;

  // String current;

  List<PangeaMatch> openMatches;

  ChoreoRecord({
    required this.choreoSteps,
    required this.openMatches,
    // required this.current,
  });

  factory ChoreoRecord.fromJson(Map<String, dynamic> json) {
    final stepsRaw = json[_stepsKey];
    return ChoreoRecord(
      choreoSteps: (jsonDecode(stepsRaw ?? "[]") as Iterable)
          .map((e) {
            return ChoreoRecordStep.fromJson(e);
          })
          .toList()
          .cast<ChoreoRecordStep>(),
      openMatches: (jsonDecode(json[_openMatchesKey] ?? "[]") as Iterable)
          .map((e) {
            return PangeaMatch.fromJson(e);
          })
          .toList()
          .cast<PangeaMatch>(),
      // current: json[_currentKey],
    );
  }

  static const _stepsKey = "stps";
  static const _openMatchesKey = "mtchs";
  // static const _currentKey = "crnt";

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    data[_stepsKey] = jsonEncode(choreoSteps.map((e) => e.toJson()).toList());
    data[_openMatchesKey] =
        jsonEncode(openMatches.map((e) => e.toJson()).toList());
    // data[_currentKey] = current;
    return data;
  }

  addRecord(String text, {PangeaMatch? match, ITStep? step}) {
    if (match != null && step != null) {
      throw Exception("match and step should not both be defined");
    }
    choreoSteps.add(
      ChoreoRecordStep(
        text: text,
        acceptedOrIgnoredMatch: match,
        itStep: step,
      ),
    );
  }

  bool get hasAcceptedMatches => choreoSteps.any(
        (element) =>
            element.acceptedOrIgnoredMatch?.status ==
            PangeaMatchStatus.accepted,
      );

  bool get hasIgnoredMatches => choreoSteps.any(
        (element) =>
            element.acceptedOrIgnoredMatch?.status == PangeaMatchStatus.ignored,
      );

  // bool get includedIT => choreoSteps.any((step) {
  //       return step.acceptedOrIgnoredMatch?.status ==
  //               PangeaMatchStatus.accepted &&
  //           (step.acceptedOrIgnoredMatch?.isITStart ?? false);
  //     });

  bool get includedIT => choreoSteps.any((step) {
        return step.acceptedOrIgnoredMatch?.status ==
                PangeaMatchStatus.accepted &&
            (step.acceptedOrIgnoredMatch?.isOutOfTargetMatch ?? false);
      });

  bool get includedIGC => choreoSteps.any((step) {
        return step.acceptedOrIgnoredMatch?.status ==
                PangeaMatchStatus.accepted &&
            (step.acceptedOrIgnoredMatch?.isGrammarMatch ?? false);
      });

  static ChoreoRecord get newRecord => ChoreoRecord(
        choreoSteps: [],
        openMatches: [],
      );

  List<ITStep> get itSteps =>
      choreoSteps.where((e) => e.itStep != null).map((e) => e.itStep!).toList();

  String get finalMessage =>
      choreoSteps.isNotEmpty ? choreoSteps.last.text : "";

  /// Get construct uses of type grammar for the message from this ChoreoRecord.
  /// Takes either an event (typically when the Representation itself is
  /// available) or construct use metadata (when the event is not available,
  /// i.e. immediately after message send) to create the construct uses.
  List<OneConstructUse> grammarConstructUses({
    Event? event,
    ConstructUseMetaData? metadata,
  }) {
    final List<OneConstructUse> uses = [];
    if (event?.roomId == null && metadata?.roomId == null) {
      return uses;
    }
    metadata ??= ConstructUseMetaData(
      roomId: event!.roomId!,
      eventId: event.eventId,
      timeStamp: event.originServerTs,
    );

    for (final step in choreoSteps) {
      if (step.acceptedOrIgnoredMatch?.status == PangeaMatchStatus.accepted) {
        final String name = step.acceptedOrIgnoredMatch!.match.rule?.id ??
            step.acceptedOrIgnoredMatch!.match.shortMessage ??
            step.acceptedOrIgnoredMatch!.match.type.typeName.name;
        uses.add(
          OneConstructUse(
            useType: ConstructUseTypeEnum.ga,
            lemma: name,
            form: name,
            constructType: ConstructTypeEnum.grammar,
            // @ggurdin what is this used for?
            id: "${metadata.eventId}_${step.acceptedOrIgnoredMatch!.match.offset}_${step.acceptedOrIgnoredMatch!.match.length}",
            metadata: metadata,
          ),
        );
      }
    }
    return uses;
  }
}

/// A new ChoreoRecordStep is saved in the following cases:
/// 1) before every system-provided text is accepted, if final text is different
/// from last step
/// 2) on the acceptance of system-provided text
/// 3) on message send, if final text is different from last step
/// 4) on the acceptance of an it step
/// 5) on the start of it
///
/// Example 1:
/// the user types "hey ther"
/// IGC suggests "there"
/// user accepts "there" correction
/// text is now "hey there"
/// A step is made for the original input 'hey there' and a step is made for system suggestion
///
/// Example 2:
/// user write "hi friend"
/// a step is made for the original input 'hi friend'
/// the user selects IT and a step is made
/// the user chooses "hola" and a step is saved
/// adds "amigo" and a step saved
class ChoreoRecordStep {
  /// text after changes have been made
  String text;

  /// all matches throughout edit process,
  /// including those open, accepted and ignored
  /// last step in list may contain open
  PangeaMatch? acceptedOrIgnoredMatch;

  ITStep? itStep;

  ChoreoRecordStep({
    required this.text,
    this.acceptedOrIgnoredMatch,
    this.itStep,
  }) {
    if (itStep != null && acceptedOrIgnoredMatch != null) {
      throw Exception(
        "itStep and acceptedOrIgnoredMatch should not both be defined",
      );
    }
  }

  factory ChoreoRecordStep.fromJson(Map<String, dynamic> json) {
    return ChoreoRecordStep(
      text: json[_textKey],
      acceptedOrIgnoredMatch: json[_acceptedOrIgnoredMatchKey] != null
          ? PangeaMatch.fromJson(json[_acceptedOrIgnoredMatchKey])
          : null,
      itStep: json[_stepKey] != null ? ITStep.fromJson(json[_stepKey]) : null,
    );
  }

  static const _textKey = "txt";
  static const _acceptedOrIgnoredMatchKey = "mtch";
  static const _stepKey = "stp";

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    data[_textKey] = text;
    data[_acceptedOrIgnoredMatchKey] = acceptedOrIgnoredMatch?.toJson();
    data[_stepKey] = itStep?.toJson();
    return data;
  }
}

// Example flow
// hello my name is Jordan! Im typing a message

// igc called, step saved with matchIndex = null

// click Im and fixed

// hello my name is Jordan! I'm typing a message

// igc called, step saved with matchIndex equal to i'm index

// hello my name is Jordan! I'm typing a message

// igc called, step saved with matchIndex = null

// class ITStepRecord {
//   List<ContinuanceRecord> allContinuances;

//   /// continuances that were clicked but not selected
//   List<int> clicked;

//   ITStepRecord({required this.continuances});
// }

// class ContinuanceRecord {}
