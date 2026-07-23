import 'package:intl/intl.dart';

class PriceFormatter {
  static String format({required String currency, required int amount}) {
    final formatter = NumberFormat.simpleCurrency(name: currency.toUpperCase());
    return formatter.format(amount / 100.0);
  }
}
