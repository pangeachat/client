enum EntitlementSource {
  rc,
  cms;

  factory EntitlementSource.fromString(String value) {
    return EntitlementSource.values.firstWhere((v) => v.name == value);
  }
}
