import 'package:flutter_test/flutter_test.dart';

import 'package:fluffychat/features/download/download_type_enum.dart';

/// A transcript downloads as plain text, CSV or an Excel workbook
/// (activity-session.instructions.md, "Downloading the transcript").
void main() {
  test('the transcript exports as TXT, CSV and XLSX', () {
    expect(DownloadType.values.map((t) => t.extension), ['txt', 'csv', 'xlsx']);
  });
}
