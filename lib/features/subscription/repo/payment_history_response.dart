class PaymentHistoryResponse {
  final List<InvoiceSummary> invoices;

  const PaymentHistoryResponse({this.invoices = const []});

  factory PaymentHistoryResponse.fromJson(Map<String, dynamic> json) {
    return PaymentHistoryResponse(
      invoices:
          (json['invoices'] as List<dynamic>?)
              ?.map((e) => InvoiceSummary.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {'invoices': invoices.map((e) => e.toJson()).toList()};
  }
}

class InvoiceSummary {
  final String id;
  final String? number;
  final String created;
  final int subtotal;
  final int total;
  final int amountPaid;
  final String currency;
  final String status;
  final String? hostedInvoiceUrl;
  final String? invoicePdf;
  final String? promoCode;

  const InvoiceSummary({
    required this.id,
    this.number,
    required this.created,
    required this.subtotal,
    required this.total,
    required this.amountPaid,
    required this.currency,
    required this.status,
    this.hostedInvoiceUrl,
    this.invoicePdf,
    this.promoCode,
  });

  factory InvoiceSummary.fromJson(Map<String, dynamic> json) {
    return InvoiceSummary(
      id: json['id'] as String,
      number: json['number'] as String?,
      created: json['created'] as String,
      subtotal: json['subtotal'] as int,
      total: json['total'] as int,
      amountPaid: json['amount_paid'] as int,
      currency: json['currency'] as String,
      status: json['status'] as String,
      hostedInvoiceUrl: json['hosted_invoice_url'] as String?,
      invoicePdf: json['invoice_pdf'] as String?,
      promoCode: json['promo_code'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'number': number,
      'created': created,
      'subtotal': subtotal,
      'total': total,
      'amount_paid': amountPaid,
      'currency': currency,
      'status': status,
      'hosted_invoice_url': hostedInvoiceUrl,
      'invoice_pdf': invoicePdf,
      'promo_code': promoCode,
    };
  }
}
