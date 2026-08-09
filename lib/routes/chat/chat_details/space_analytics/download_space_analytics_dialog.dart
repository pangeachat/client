import 'package:flutter/material.dart';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/features/analytics/construct_use_model.dart';
import 'package:fluffychat/features/analytics/saved_analytics_extension.dart';
import 'package:fluffychat/features/analytics_data/analytics_settings_extension.dart';
import 'package:fluffychat/features/download/download_dialog.dart';
import 'package:fluffychat/features/download/download_file_util.dart';
import 'package:fluffychat/features/download/download_type_enum.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension.dart';
import 'package:fluffychat/pangea/morphs/grammar_constructs_provider.dart';
import 'package:fluffychat/routes/chat/chat_details/space_analytics/space_analytics_summary_enum.dart';
import 'package:fluffychat/routes/chat/chat_details/space_analytics/space_analytics_summary_model.dart';
import 'package:fluffychat/widgets/matrix.dart';

class DownloadAnalyticsDialog extends StatefulWidget {
  final Room space;
  final List<Room> analyticsRooms;
  const DownloadAnalyticsDialog({
    required this.space,
    required this.analyticsRooms,
    super.key,
  });

  @override
  DownloadAnalyticsDialogState createState() => DownloadAnalyticsDialogState();
}

class DownloadAnalyticsDialogState extends State<DownloadAnalyticsDialog> {
  bool _initialized = false;
  bool _downloaded = false;
  bool _downloading = false;

  bool get _loading => _downloading || !_initialized;

  Object? _error;

  Map<String, int> _downloadStatuses = {};

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    _downloadStatuses = Map.fromEntries(
      widget.analyticsRooms.map((room) => MapEntry(room.creatorId!, 0)),
    );
    if (mounted) setState(() => _initialized = true);
  }

  DownloadType _downloadType = DownloadType.csv;

  void _setDownloadType(DownloadType type) {
    _clean();
    if (mounted) setState(() => _downloadType = type);
  }

  void _clean() {
    _error = null;
    _downloading = false;
    _downloaded = false;
    _downloadStatuses = Map.fromEntries(
      widget.analyticsRooms.map((room) => MapEntry(room.creatorId!, 0)),
    );
  }

  Color _downloadStatusColor(String userID) {
    final status = _downloadStatuses[userID];
    if (status == 1) return Colors.yellow;
    if (status == 2) return Colors.green;
    if ((status ?? 0) < 0) return Colors.red;
    return Colors.grey;
  }

  String? get userL2 =>
      MatrixState.pangeaController.userController.userL2?.langCode;

  Future<void> _runDownload() async {
    try {
      if (!mounted || userL2 == null) return;
      setState(() {
        _error = null;
        _downloading = true;
      });

      final List<SpaceAnalyticsSummaryModel> summaries = [];
      for (final room in widget.analyticsRooms) {
        final summary = await _getAnalyticsModel(room);
        if (summary != null) {
          summaries.add(summary);
        }
      }

      for (final userID in _downloadStatuses.keys) {
        if (_downloadStatuses[userID] == 0) {
          _downloadStatuses[userID] = -1;
          summaries.add(SpaceAnalyticsSummaryModel.emptyModel(userID));
        }
      }

      await _downloadSpaceAnalytics(summaries);

      if (mounted) {
        setState(() {
          _downloading = false;
          _downloaded = true;
        });
      }
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {});

      _clean();
      _error = e;
      if (mounted) setState(() {});
    }
  }

  Future<void> _downloadSpaceAnalytics(
    List<SpaceAnalyticsSummaryModel> summaries,
  ) async {
    final content = _downloadType == DownloadType.xlsx
        ? _getExcelFileContent(summaries)
        : _getCSVFileContent(summaries);

    final fileName =
        "analytics_${widget.space.name}_${DateTime.now().toIso8601String()}.${_downloadType == DownloadType.xlsx ? 'xlsx' : 'csv'}";

    await DownloadUtil.downloadFile(content, fileName, DownloadType.csv);
  }

  Future<SpaceAnalyticsSummaryModel?> _getAnalyticsModel(
    Room analyticsRoom,
  ) async {
    final String? userID = analyticsRoom.creatorId;
    if (userID == null) return null;

    SpaceAnalyticsSummaryModel? summary;
    try {
      _downloadStatuses[userID] = 1;
      if (mounted) setState(() {});

      final constructEvents = await analyticsRoom.getAnalyticsEvents(
        userId: userID,
      );

      if (constructEvents == null) {
        if (mounted) setState(() => _downloadStatuses[userID] = -1);
        return SpaceAnalyticsSummaryModel.emptyModel(userID);
      }
      summary = SpaceAnalyticsSummaryModel.fromEvents(
        userID,
        constructEvents,
        analyticsRoom.blockedConstructs,
        analyticsRoom.archivedActivitiesCount,
      );
      if (mounted) setState(() => _downloadStatuses[userID] = 2);
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {"userID": userID});
      if (mounted) setState(() => _downloadStatuses[userID] = -2);
    }

    return summary;
  }

  List<CellValue> _formatExcelRow(SpaceAnalyticsSummaryModel summary) {
    final List<CellValue> row = [];
    for (int i = 0; i < SpaceAnalyticsSummaryEnum.values.length; i++) {
      final key = SpaceAnalyticsSummaryEnum.values[i];
      final value = summary.getValue(key, context);
      if (value is int) {
        row.add(IntCellValue(value));
      } else if (value is String) {
        row.add(TextCellValue(value));
      } else if (value is List<String>) {
        row.add(TextCellValue(value.join(", ")));
      }
    }
    return row;
  }

  List<int> _getExcelFileContent(List<SpaceAnalyticsSummaryModel> summaries) {
    final excel = Excel.createExcel();
    final sheet = excel['Sheet1'];

    for (final key in SpaceAnalyticsSummaryEnum.values) {
      sheet
          .cell(CellIndex.indexByColumnRow(rowIndex: 0, columnIndex: key.index))
          .value = TextCellValue(
        key.header(L10n.of(context)),
      );
    }

    final rows = summaries.map((summary) => _formatExcelRow(summary)).toList();

    for (int i = 0; i < rows.length; i++) {
      final row = rows[i];
      for (int j = 0; j < row.length; j++) {
        final cell = row[j];
        sheet
                .cell(
                  CellIndex.indexByColumnRow(rowIndex: i + 2, columnIndex: j),
                )
                .value =
            cell;
      }
    }
    return excel.encode() ?? [];
  }

  String _getCSVFileContent(List<SpaceAnalyticsSummaryModel> summaries) {
    final List<List<dynamic>> rows = [];
    final headerRow = [];
    for (final key in SpaceAnalyticsSummaryEnum.values) {
      headerRow.add(key.header(L10n.of(context)));
    }
    rows.add(headerRow);

    for (final summary in summaries) {
      final row = [];
      for (int i = 0; i < SpaceAnalyticsSummaryEnum.values.length; i++) {
        final key = SpaceAnalyticsSummaryEnum.values[i];
        final value = summary.getValue(key, context);
        if (value == null) continue;
        value is List<String> ? row.add(value.join(", ")) : row.add(value);
      }
      rows.add(row);
    }

    final String fileString = const ListToCsvConverter().convert(rows);
    return fileString;
  }

  String getCopy(ConstructUses use) {
    return GrammarConstructsProvider.getTagTitle(
          feature: use.category,
          tag: use.lemma,
        ) ??
        use.lemma;
  }

  @override
  Widget build(BuildContext context) {
    final enableDownload = !_downloading && !_loading && _initialized;
    final errorMessage = _error != null
        ? L10n.of(context).errorDownloading
        : null;

    final content = ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 300, minHeight: 0),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: widget.analyticsRooms.length,
        itemBuilder: (context, index) {
          final userId = widget.analyticsRooms[index].creatorId;

          String tooltip = "";
          if (_downloadStatuses[userId] == -1) {
            tooltip = L10n.of(context).analyticsNotAvailable;
          } else if (_downloadStatuses[userId] == -2) {
            tooltip = L10n.of(context).failedFetchUserAnalytics;
          }

          return Padding(
            padding: const EdgeInsets.all(4.0),
            child: AnimatedOpacity(
              duration: FluffyThemes.animationDuration,
              opacity: (_downloadStatuses[userId] ?? 0) > 0 ? 1 : 0.5,
              child: Row(
                children: [
                  SizedBox(
                    width: 40,
                    height: 30,
                    child: (_downloadStatuses[userId] ?? 0) < 0
                        ? const Icon(Icons.error_outline, size: 16)
                        : Center(
                            child: AnimatedContainer(
                              duration: FluffyThemes.animationDuration,
                              height: 12,
                              width: 12,
                              decoration: BoxDecoration(
                                color: _downloadStatusColor(userId!),
                                borderRadius: BorderRadius.circular(100),
                              ),
                            ),
                          ),
                  ),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(userId!),
                        if (tooltip.isNotEmpty)
                          Text(tooltip, style: const TextStyle(fontSize: 10)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    return DownloadDialog(
      downloading: _downloading,
      downloaded: _downloaded,
      enableDownload: enableDownload,
      selectedDownloadType: _downloadType,
      downloadableTypes: [DownloadType.csv, DownloadType.xlsx],
      setDownloadType: _setDownloadType,
      download: _runDownload,
      error: errorMessage,
      description: L10n.of(context).courseAnalyticsDownloadDesc,
      content: content,
    );
  }
}
