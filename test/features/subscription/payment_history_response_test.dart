import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/subscription/repo/payment_history_response.dart';

// Verifies the client InvoiceSummary matches the REAL v2 `/subscription/history`
// shape (choreo InvoiceHistoryResponse): total/subtotal/amount_paid in minor
// units, `created` as a Zulu ISO-8601 STRING (not a unix int), the nullable
// url/number/promo fields, and NO single `amount` field.
void main() {
  group('InvoiceSummary.fromJson', () {
    test('parses a full paid invoice (money in minor units)', () {
      final inv = InvoiceSummary.fromJson({
        "id": "in_123",
        "number": "ABCD-0001",
        "created": "2026-07-01T12:00:00Z",
        "subtotal": 999,
        "total": 999,
        "amount_paid": 999,
        "currency": "usd",
        "status": "paid",
        "hosted_invoice_url": "https://pay.stripe.com/invoice/abc",
        "invoice_pdf": "https://pay.stripe.com/invoice/abc/pdf",
        "promo_code": null,
      });

      expect(inv.id, "in_123");
      expect(inv.number, "ABCD-0001");
      // Zulu ISO string, not an int — and re-parseable as a DateTime.
      expect(inv.created, "2026-07-01T12:00:00Z");
      expect(DateTime.parse(inv.created).isUtc, true);
      expect(inv.subtotal, 999);
      expect(inv.total, 999);
      expect(inv.amountPaid, 999);
      expect(inv.currency, "usd");
      expect(inv.status, "paid");
      expect(inv.hostedInvoiceUrl, "https://pay.stripe.com/invoice/abc");
      expect(inv.invoicePdf, "https://pay.stripe.com/invoice/abc/pdf");
      expect(inv.promoCode, isNull);
    });

    test('tolerates null number / urls / promo_code', () {
      final inv = InvoiceSummary.fromJson({
        "id": "in_456",
        "number": null,
        "created": "2026-06-15T08:30:00Z",
        "subtotal": 8999,
        "total": 8999,
        "amount_paid": 0,
        "currency": "eur",
        "status": "open",
        "hosted_invoice_url": null,
        "invoice_pdf": null,
        "promo_code": null,
      });

      expect(inv.number, isNull);
      expect(inv.hostedInvoiceUrl, isNull);
      expect(inv.invoicePdf, isNull);
      expect(inv.promoCode, isNull);
      expect(inv.amountPaid, 0);
      expect(inv.status, "open");
    });

    test('there is NO single `amount` field on the invoice model', () {
      // Guards against a regression to the pre-v2 shape (which had `amount`).
      final json = InvoiceSummary.fromJson({
        "id": "in_789",
        "created": "2026-05-01T00:00:00Z",
        "subtotal": 100,
        "total": 100,
        "amount_paid": 100,
        "currency": "usd",
        "status": "paid",
      }).toJson();

      expect(json.containsKey("amount"), false);
      expect(json.keys, containsAll(["subtotal", "total", "amount_paid"]));
    });
  });

  group('numeric leniency (serializer may emit 999.0 for 999)', () {
    test('double-valued minor-unit amounts parse to ints', () {
      final inv = InvoiceSummary.fromJson({
        "id": "in_dbl",
        "created": "2026-07-01T12:00:00Z",
        "subtotal": 999.0,
        "total": 999.0,
        "amount_paid": 999.0,
        "currency": "usd",
        "status": "paid",
      });

      expect(inv.subtotal, 999);
      expect(inv.total, 999);
      expect(inv.amountPaid, 999);
    });
  });

  group('PaymentHistoryResponse.fromJson', () {
    test('parses a list of invoices', () {
      final res = PaymentHistoryResponse.fromJson({
        "invoices": [
          {
            "id": "in_1",
            "created": "2026-07-01T12:00:00Z",
            "subtotal": 999,
            "total": 999,
            "amount_paid": 999,
            "currency": "usd",
            "status": "paid",
          },
          {
            "id": "in_2",
            "created": "2026-06-01T12:00:00Z",
            "subtotal": 999,
            "total": 999,
            "amount_paid": 999,
            "currency": "usd",
            "status": "paid",
          },
        ],
      });

      expect(res.invoices, hasLength(2));
      expect(res.invoices.first.id, "in_1");
    });

    test('no customers -> an empty invoices list', () {
      expect(
        PaymentHistoryResponse.fromJson({"invoices": []}).invoices,
        isEmpty,
      );
      // Missing key also degrades to empty (defensive).
      expect(PaymentHistoryResponse.fromJson({}).invoices, isEmpty);
    });
  });
}
