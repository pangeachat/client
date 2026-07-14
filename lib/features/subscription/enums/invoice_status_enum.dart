enum InvoiceStatus {
  paid,
  open,
  voided,
  uncollectible,
  draft;

  factory InvoiceStatus.fromString(String value) {
    return InvoiceStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => InvoiceStatus.open,
    );
  }
}
