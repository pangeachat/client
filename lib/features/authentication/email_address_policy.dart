/// The homeserver's signup email address policy, mirrored so the form can
/// answer immediately instead of waiting for a round trip.
///
/// This is a copy of a rule the homeserver owns, never the gate: the same rule
/// is enforced on every server path that can send a verification email. A
/// change to what Pangea accepts is decided in the server's
/// `email-address-policy.instructions.md` first.
class EmailAddressPolicy {
  /// Mail servers in practice refuse addresses longer than this.
  static const int maxAddressLength = 254;

  /// How long the resend control stays disabled after a verification email has
  /// been sent, so repeated taps cannot each trigger one.
  static const Duration resendCooldown = Duration(seconds: 30);

  /// A domain label: starts and ends alphanumeric, hyphens allowed inside.
  /// Unicode-aware, so an internationalised domain typed in its native script
  /// is accepted alongside its punycode form.
  static final RegExp _label = RegExp(
    r'^[\p{L}\p{N}](?:[\p{L}\p{N}]|-)*$',
    unicode: true,
  );

  /// Two or more letters, so that "a@b.c" and "a@b.11" are refused.
  static final RegExp _topLevelLabel = RegExp(r'^\p{L}{2,}$', unicode: true);

  /// Deliberately looser than the email address standard: it exists to catch
  /// obvious junk before it costs a bounce, and rejecting a real learner's
  /// unusual address is a worse outcome than letting one junk address through.
  static bool isValid(String address) {
    if (address.length > maxAddressLength) return false;

    final separator = address.lastIndexOf('@');
    if (separator <= 0 || separator == address.length - 1) return false;

    final localPart = address.substring(0, separator);
    if (localPart.contains('@')) return false;
    if (address.contains(RegExp(r'\s'))) return false;

    final labels = address.substring(separator + 1).split('.');
    // At least two labels, so that "a@b" is refused.
    if (labels.length < 2) return false;
    if (!labels.every(_label.hasMatch)) return false;
    if (labels.any((label) => label.endsWith('-'))) return false;

    return _topLevelLabel.hasMatch(labels.last);
  }
}
