import 'package:fluffychat/routes/chat/chat_details/space_analytics/space_analytics_download_enum.dart';
import 'package:fluffychat/routes/chat/chat_details/space_analytics/space_analytics_summary_model.dart';

class AnalyticsDownload {
  RequestStatus requestStatus;
  DownloadStatus downloadStatus;
  SpaceAnalyticsSummaryModel? summary;

  AnalyticsDownload({
    required this.requestStatus,
    required this.downloadStatus,
    this.summary,
  });
}
