import 'package:intl/intl.dart';

class DateFormatter {
  static final _formatter = DateFormat('yyyy-MM-dd');
  static String format(DateTime date) => _formatter.format(date);
}
