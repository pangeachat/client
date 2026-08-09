// ignore_for_file: constant_identifier_names

enum ManageActionKind {
  portal,
  update_payment;

  factory ManageActionKind.fromString(String value) {
    return ManageActionKind.values.firstWhere((e) => e.name == value);
  }
}
