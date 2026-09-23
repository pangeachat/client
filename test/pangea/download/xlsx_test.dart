import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/download/xlsx.dart';

void main() {
  test('writes the header to row 0 and the data from row 2', () {
    final time = DateTime(2026, 9, 23, 14, 5, 9);
    final excel = Excel.decodeBytes(
      encodeXlsx({
        'Sheet1': [
          ['Sender', 'Time', 'Count', 'Note'],
          ['@a:x', time, 3, null],
        ],
      }),
    );

    expect(excel.tables.keys, ['Sheet1']);
    final rows = excel.tables['Sheet1']!.rows
        .map((row) => row.map((cell) => cell?.value).toList())
        .toList();
    expect(rows, [
      [
        TextCellValue('Sender'),
        TextCellValue('Time'),
        TextCellValue('Count'),
        TextCellValue('Note'),
      ],
      [null, null, null, null],
      [
        TextCellValue('@a:x'),
        DateTimeCellValue.fromDateTime(time),
        const IntCellValue(3),
        null,
      ],
    ]);
  });

  test('named sheets replace Sheet1 and the first one opens', () {
    final excel = Excel.decodeBytes(
      encodeXlsx({
        'Vocabulary': [
          ['Lemma'],
          ['comer'],
        ],
        'Grammar': [
          ['Tag'],
          ['Past'],
        ],
      }),
    );

    expect(excel.tables.keys, ['Vocabulary', 'Grammar']);
    expect(excel.getDefaultSheet(), 'Vocabulary');
  });

  test('a value that is not a cell type fails loudly', () {
    expect(
      () => encodeXlsx({
        'Sheet1': [
          ['Score'],
          [1.5],
        ],
      }),
      throwsArgumentError,
    );
  });
}
