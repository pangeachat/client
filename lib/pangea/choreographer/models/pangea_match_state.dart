import 'package:fluffychat/pangea/choreographer/enums/pangea_match_status.dart';
import 'package:fluffychat/pangea/choreographer/models/pangea_match_model.dart';
import 'package:fluffychat/pangea/choreographer/models/span_data.dart';

class PangeaMatchState {
  final PangeaMatch _original;
  SpanData _match;
  PangeaMatchStatus _status;

  PangeaMatchState({
    required PangeaMatch original,
    required SpanData match,
    required PangeaMatchStatus status,
  })  : _original = original,
        _match = match,
        _status = status;

  PangeaMatch get originalMatch => _original;

  PangeaMatch get updatedMatch => PangeaMatch(
        match: _match,
        status: _status,
      );

  void setStatus(PangeaMatchStatus status) {
    _status = status;
  }

  void setMatch(SpanData match) {
    _match = match;
  }

  void selectChoice(int index) {
    final choices = List<SpanChoice>.from(_match.choices ?? []);
    choices[index] = choices[index].copyWith(
      selected: true,
      timestamp: DateTime.now(),
    );
    setMatch(_match.copyWith(choices: choices));
  }

  Map<String, dynamic> toJson() {
    return {
      'originalMatch': _original.toJson(),
      'match': _match.toJson(),
      'status': _status.toString(),
    };
  }
}
