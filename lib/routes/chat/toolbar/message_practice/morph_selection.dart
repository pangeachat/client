import 'package:fluffychat/pangea/morphs/morph_features_enum.dart';
import 'package:fluffychat/routes/chat/events/models/pangea_token_model.dart';

class MorphSelection {
  PangeaToken token;
  MorphFeaturesEnum morph;

  MorphSelection(this.token, this.morph);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is MorphSelection &&
        other.token == token &&
        other.morph == morph;
  }

  @override
  int get hashCode => token.hashCode ^ morph.hashCode;
}
