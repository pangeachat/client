import 'package:fluffychat/pangea/choreographer/enums/pangea_match_status.dart';
import 'package:fluffychat/pangea/choreographer/models/igc_text_state.dart';
import 'package:fluffychat/pangea/choreographer/models/pangea_match_model.dart';
import 'package:fluffychat/pangea/choreographer/models/pangea_match_state.dart';
import 'package:fluffychat/pangea/choreographer/models/span_data.dart';

class IGCTextData {
  final String _originalInput;
  final List<PangeaMatch> _matches;
  final IGCTextState _state;

  IGCTextData({
    required String originalInput,
    required List<PangeaMatch> matches,
  })  : _state = IGCTextState(
          currentText: originalInput,
          matches: List<PangeaMatch>.from(matches),
        ),
        _originalInput = originalInput,
        _matches = matches;

  Map<String, dynamic> toJson() => {
        "original_input": _originalInput,
        "matches": _matches.map((e) => e.toJson()).toList(),
      };

  bool get hasOpenMatches => _state.hasOpenMatches;

  bool get hasOpenITMatches => _state.hasOpenITMatches;

  bool get hasOpenIGCMatches => _state.hasOpenIGCMatches;

  String get currentText => _state.currentText;

  List<PangeaMatchState> get openMatches => _state.openMatches;

  List<PangeaMatchState> get recentNormalizationMatches =>
      _state.recentNormalizationMatches;

  PangeaMatchState? get firstOpenMatch => _state.firstOpenMatch;

  PangeaMatchState? get openMatch => _state.openMatch;

  PangeaMatchState? getMatchByOffset(int offset) =>
      _state.getMatchByOffset(offset);

  List<PangeaMatchState> get openNormalizationMatches =>
      _state.openNormalizationMatches;

  void clearMatches() => _state.clearMatches();

  void setSpanData(PangeaMatchState match, SpanData spanData) {
    _state.setSpanData(match, spanData);
  }

  PangeaMatch acceptReplacement(
    PangeaMatchState match,
    PangeaMatchStatus status,
  ) =>
      _state.acceptReplacement(match, status);

  PangeaMatch ignoreReplacement(PangeaMatchState match) =>
      _state.ignoreReplacement(match);

  void undoReplacement(PangeaMatchState match) => _state.undoReplacement(match);
}
