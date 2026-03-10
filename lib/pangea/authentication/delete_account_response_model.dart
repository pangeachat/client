import 'package:fluffychat/pangea/authentication/delete_account_action_enum.dart';

class DeleteAccountResponseModel {
  final String message;
  final DeleteAccountAction action;
  final String userId;
  final int? executeAtMs;
  final bool? canceled;
  final int? deletedExternalIds;
  final int? deletedThreepids;

  DeleteAccountResponseModel({
    required this.message,
    required this.action,
    required this.userId,
    this.executeAtMs,
    this.canceled,
    this.deletedExternalIds,
    this.deletedThreepids,
  });

  Map<String, dynamic> toJson() {
    return {
      'message': message,
      'action': action.name,
      'user_id': userId,
      if (executeAtMs != null) 'execute_at_ms': executeAtMs,
      if (canceled != null) 'canceled': canceled,
      if (deletedExternalIds != null)
        'deleted_external_ids': deletedExternalIds,
      if (deletedThreepids != null) 'deleted_threepids': deletedThreepids,
    };
  }

  factory DeleteAccountResponseModel.fromJson(Map<String, dynamic> json) {
    return DeleteAccountResponseModel(
      message: json['message'] as String,
      action: DeleteAccountAction.values.firstWhere(
        (e) => e.name == json['action'],
        orElse: () => throw Exception('Unknown action type: ${json['action']}'),
      ),
      userId: json['user_id'] as String,
      executeAtMs: json['execute_at_ms'] as int?,
      canceled: json['canceled'] as bool?,
      deletedExternalIds: json['deleted_external_ids'] as int?,
      deletedThreepids: json['deleted_threepids'] as int?,
    );
  }
}
