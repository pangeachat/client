import 'package:fluffychat/features/network_filter/network_host_category.dart';
import 'package:fluffychat/features/network_filter/network_type.dart';

/// A user's request for help with a network that blocks the app, sent to the
/// team as a CMS form submission. See filtered-network.instructions.md,
/// "Asking Pangea for help".
class NetworkHelpRequest {
  /// The CMS form type the team notification email is keyed on.
  static const String formType = 'network-help';

  final String email;

  /// The Matrix user ID, when the user is signed in.
  final String? accountId;

  final List<NetworkHostCategory> blockedCategories;
  final String platform;
  final NetworkType networkType;

  /// When the first of [blockedCategories] was seen blocked — not when the
  /// request is sent, which may be later and from another network.
  final DateTime firstBlockedAt;

  const NetworkHelpRequest({
    required this.email,
    required this.accountId,
    required this.blockedCategories,
    required this.platform,
    required this.networkType,
    required this.firstBlockedAt,
  });

  /// The body the CMS `form-submissions` collection accepts. The collection
  /// requires a name; the account ID stands in for one, or the email when the
  /// user is signed out.
  Map<String, dynamic> toFormSubmission() => {
    'formType': formType,
    'name': accountId ?? email,
    'email': email,
    'data': _details,
  };

  Map<String, dynamic> get _details => {
    'accountId': accountId,
    'blockedCategories': [for (final c in blockedCategories) c.name],
    'platform': platform,
    'networkType': networkType.name,
    'firstBlockedAt': firstBlockedAt.toUtc().toIso8601String(),
  };

  Map<String, dynamic> toJson() => {'email': email, ..._details};

  factory NetworkHelpRequest.fromJson(Map<String, dynamic> json) =>
      NetworkHelpRequest(
        email: json['email'] as String,
        accountId: json['accountId'] as String?,
        blockedCategories: [
          for (final name in json['blockedCategories'] as List)
            NetworkHostCategory.values.byName(name as String),
        ],
        platform: json['platform'] as String,
        networkType: NetworkType.values.byName(json['networkType'] as String),
        firstBlockedAt: DateTime.parse(json['firstBlockedAt'] as String),
      );
}
