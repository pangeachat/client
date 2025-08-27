import 'package:fluffychat/pangea/payload_client/payload_client.dart';
import 'package:fluffychat/pangea/payload_client/string_or_t.dart';

Future<T?> extractFromStringOrT<T>(
  StringOr<T> stringOr,
  String collection,
  PayloadClient payload,
  T Function(Map<String, dynamic>) fromJson,
) async {
  if (stringOr.runtimeType.toString().contains('_ValueCase')) {
    final valueCase = stringOr as dynamic;
    return valueCase.value as T;
  }
  return payload.findById(collection, stringOr as String, fromJson);
}
