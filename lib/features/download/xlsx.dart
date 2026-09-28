import 'package:excel/excel.dart';

/// Builds an .xlsx workbook from [sheets], each a sheet name mapped to its
/// rows. The first row is the header and goes to row 0; the rest start at
/// row 2, leaving row 1 blank as the exports always have.
///
/// A cell is a [String], an [int], a [DateTime], or null for an empty cell.
/// A workbook with no `Sheet1` among [sheets] opens on its first sheet.
///
/// Import this file `deferred`: it is the client's only use of
/// `package:excel`, and deferring it keeps that package out of the startup
/// web bundle (#9233).
List<int> encodeXlsx(Map<String, List<List<Object?>>> sheets) {
  final excel = Excel.createExcel();
  for (final MapEntry(key: name, value: rows) in sheets.entries) {
    final sheet = excel[name];
    for (var r = 0; r < rows.length; r++) {
      final rowIndex = r == 0 ? 0 : r + 1;
      for (var c = 0; c < rows[r].length; c++) {
        final value = _cellValue(rows[r][c]);
        if (value == null) continue;
        sheet
                .cell(
                  CellIndex.indexByColumnRow(
                    columnIndex: c,
                    rowIndex: rowIndex,
                  ),
                )
                .value =
            value;
      }
    }
  }
  if (!sheets.containsKey(_initialSheet)) {
    excel.setDefaultSheet(sheets.keys.first);
    excel.delete(_initialSheet);
  }
  final bytes = excel.encode();
  if (bytes == null) throw StateError('excel.encode() returned no bytes');
  return bytes;
}

/// The sheet [Excel.createExcel] starts every workbook with.
const _initialSheet = 'Sheet1';

CellValue? _cellValue(Object? value) => switch (value) {
  null => null,
  String() => TextCellValue(value),
  int() => IntCellValue(value),
  DateTime() => DateTimeCellValue(
    year: value.year,
    month: value.month,
    day: value.day,
    hour: value.hour,
    minute: value.minute,
    second: value.second,
  ),
  _ => throw ArgumentError.value(value, 'value', 'not an xlsx cell'),
};
