import 'package:intl/intl.dart';

class PriceFormatter {
  static final NumberFormat _formatter = NumberFormat();
  static String format({required String currency, required int amount}) {
    final updatedAmount = amount / 100;
    final symbol = _formatter.simpleCurrencySymbol(currency.toUpperCase());
    return "$symbol$updatedAmount";
  }
}
