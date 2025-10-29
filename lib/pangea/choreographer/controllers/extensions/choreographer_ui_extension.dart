import 'package:fluffychat/pangea/choreographer/controllers/choreographer.dart';
import 'package:fluffychat/pangea/common/utils/any_state_holder.dart';
import 'package:fluffychat/widgets/matrix.dart';

extension ChoregrapherUserSettingsExtension on Choreographer {
  LayerLinkAndKey get itBarLinkAndKey =>
      MatrixState.pAnyState.layerLinkAndKey(itBarTransformTargetKey);
  String get itBarTransformTargetKey => 'it_bar${chatController.roomId}';
  LayerLinkAndKey get inputLayerLinkAndKey =>
      MatrixState.pAnyState.layerLinkAndKey(inputTransformTargetKey);
  String get inputTransformTargetKey => 'input${chatController.roomId}';
}
