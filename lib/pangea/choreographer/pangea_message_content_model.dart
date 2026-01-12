import 'package:fluffychat/pangea/choreographer/choreo_record_model.dart';
import 'package:fluffychat/pangea/events/models/representation_content_model.dart';
import 'package:fluffychat/pangea/events/models/tokens_event_content_model.dart';

class PangeaMessageContentModel {
  final String message;
  final PangeaRepresentation? originalWritten;
  final PangeaMessageTokens? tokensSent;
  final PangeaMessageTokens? tokensWritten;
  final ChoreoRecordModel? choreo;

  const PangeaMessageContentModel({
    required this.message,
    this.originalWritten,
    this.tokensSent,
    this.tokensWritten,
    this.choreo,
  });
}
