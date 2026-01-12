import 'package:fluffychat/pangea/choreographer/igc/span_data_model.dart';
import 'package:fluffychat/pangea/common/constants/model_keys.dart';

class SpanDetailsRequest {
  final String userL1;
  final String userL2;
  final bool enableIT;
  final bool enableIGC;
  final SpanData span;

  const SpanDetailsRequest({
    required this.userL1,
    required this.userL2,
    required this.enableIGC,
    required this.enableIT,
    required this.span,
  });

  Map<String, dynamic> toJson() => {
        ModelKey.userL1: userL1,
        ModelKey.userL2: userL2,
        ModelKey.enableIT: enableIT,
        ModelKey.enableIGC: enableIGC,
        'span': span.toJson(),
      };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SpanDetailsRequest) return false;
    if (other.userL1 != userL1) return false;
    if (other.userL2 != userL2) return false;
    if (other.enableIT != enableIT) return false;
    if (other.enableIGC != enableIGC) return false;
    if (other.span != span) return false;
    return true;
  }

  @override
  int get hashCode {
    return userL1.hashCode ^
        userL2.hashCode ^
        enableIT.hashCode ^
        enableIGC.hashCode ^
        span.hashCode;
  }
}
