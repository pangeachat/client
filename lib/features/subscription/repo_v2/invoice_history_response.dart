import 'package:fluffychat/features/subscription/enums/invoice_status_enum.dart';
import 'package:fluffychat/pangea/common/utils/base_response.dart';

class InvoiceHistoryResponse extends BaseResponse {
  final List<Invoice> invoices;

  const InvoiceHistoryResponse({required this.invoices});

  factory InvoiceHistoryResponse.fromJson(Map<String, dynamic> json) {
    return InvoiceHistoryResponse(
      invoices: (json['invoices'] as List<dynamic>? ?? [])
          .map((e) => Invoice.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {'invoices': invoices.map((e) => e.toJson()).toList()};
  }
}

class Invoice {
  final String id;
  final String? number;
  final DateTime created;
  final int subtotal;
  final int total;
  final int amountPaid;
  final String currency;
  final InvoiceStatus status;
  final String? hostedInvoiceUrl;
  final String? invoicePdf;
  final String? promoCode;

  const Invoice({
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

  factory Invoice.fromJson(Map<String, dynamic> json) {
    return Invoice(
      id: json['id'] as String,
      number: json['number'] as String?,
      created: DateTime.parse(json['created'] as String),
      subtotal: json['subtotal'] as int,
      total: json['total'] as int,
      amountPaid: json['amount_paid'] as int,
      currency: json['currency'] as String,
      status: InvoiceStatus.fromString(json['status'] as String),
      hostedInvoiceUrl: json['hosted_invoice_url'] as String?,
      invoicePdf: json['invoice_pdf'] as String?,
      promoCode: json['promo_code'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'number': number,
      'created': created.toIso8601String(),
      'subtotal': subtotal,
      'total': total,
      'amount_paid': amountPaid,
      'currency': currency,
      'status': status.name,
      'hosted_invoice_url': hostedInvoiceUrl,
      'invoice_pdf': invoicePdf,
      'promo_code': promoCode,
    };
  }
}
