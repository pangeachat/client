enum InvoiceStatus {
  paid,
  open,
  voided,
  uncollectible,
  draft;

  factory InvoiceStatus.fromString(String value) {
    if (value == 'void') return InvoiceStatus.voided;
    return InvoiceStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => InvoiceStatus.open,
    );
  }
}
