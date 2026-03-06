import 'package:fluffychat/pangea/common/constants/model_keys.dart';
import 'package:fluffychat/pangea/learning_settings/gender_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// Base request schema matching the backend's BaseRequestSchema.
/// Common fields for all LLM-based requests.
mixin BaseRequestModel {
  /// User's native language code (L1)
  String get userL1;

  /// User's target language code (L2)
  String get userL2;

  /// User's CEFR proficiency level (defaults to "pre_a1")
  String get userCefr;

  /// Convert to JSON map with common fields
  Map<String, dynamic> toBaseJson() => {
    ModelKey.userL1: userL1,
    ModelKey.userL2: userL2,
    ModelKey.cefrLevel: userCefr,
    ModelKey.userGender: MatrixState
        .pangeaController
        .userController
        .profile
        .userSettings
        .gender
        .string,
  };

  /// Injects user context (CEFR level, gender) into a request body.
  /// Safely handles cases where MatrixState is not yet initialized.
  /// Does not overwrite existing values.
  static Map<String, dynamic> injectUserContext(Map<dynamic, dynamic> body) {
    final result = Map<String, dynamic>.from(body);
    try {
      final settings =
          MatrixState.pangeaController.userController.profile.userSettings;
      result[ModelKey.cefrLevel] ??= settings.cefrLevel.string;
      result[ModelKey.userGender] ??= settings.gender.string;
    } catch (_) {
      // MatrixState not initialized - leave existing values or omit
    }
    return result;
  }
}
