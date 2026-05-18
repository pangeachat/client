import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/events/constants/pangea_event_types.dart';

enum AnalyticsRoomStatus { canonical, merged }

class AnalyticsStatusModel {
  final AnalyticsRoomStatus status;
  const AnalyticsStatusModel({required this.status});

  bool get isCanonical => status == AnalyticsRoomStatus.canonical;

  AnalyticsStatusModel copyWith({AnalyticsRoomStatus? status}) =>
      AnalyticsStatusModel(status: status ?? this.status);

  Map<String, dynamic> toJson() => {"status": status.name};

  factory AnalyticsStatusModel.fromJson(Map<String, dynamic> json) =>
      AnalyticsStatusModel(
        status:
            AnalyticsRoomStatus.values.firstWhereOrNull(
              (v) => v.name == json["status"],
            ) ??
            AnalyticsRoomStatus.canonical,
      );
}

extension AnalyticsStatusRoomExtension on Room {
  AnalyticsStatusModel get analyticsStatus {
    final state = getState(PangeaEventTypes.analyticsStatus);
    if (state == null) {
      return AnalyticsStatusModel(status: AnalyticsRoomStatus.canonical);
    }

    try {
      return AnalyticsStatusModel.fromJson(state.content);
    } catch (_) {
      return AnalyticsStatusModel(status: AnalyticsRoomStatus.canonical);
    }
  }

  Future<void> _setAnalyticsStatus(AnalyticsStatusModel model) =>
      client.setRoomStateWithKey(
        id,
        PangeaEventTypes.analyticsStatus,
        '',
        model.toJson(),
      );

  Future<void> markAnalyticsRoomMerged() => _setAnalyticsStatus(
    analyticsStatus.copyWith(status: AnalyticsRoomStatus.merged),
  );
}
