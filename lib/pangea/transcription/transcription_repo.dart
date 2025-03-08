import 'dart:convert';

import 'package:fluffychat/pages/chat/recording_dialog.dart';
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:http/http.dart';
import 'package:web_socket_channel/io.dart';

class TranscriptionRepo {
  static Future<IOWebSocketChannel> connectTranscriptionChannel() async {
    final Requests reqToken = Requests(
      choreoApiKey: Environment.choreoApiKey,
      accessToken: MatrixState.pangeaController.userController.accessToken,
    );

    final Response resToken = await reqToken.get(
      url: PApiUrls.realtimeTranscriptionSession,
    );
    final json = jsonDecode(resToken.body);
    final String key = json['key'];

    final uri = Uri(
      scheme: 'wss',
      host: 'api.deepgram.com',
      path: 'v1/listen',
      queryParameters: {
        'encoding': 'linear16',
        'sample_rate': '${RecordingDialogState.samplingRateTranscription}',
        'endpointing': 'false',
        // TODO: accept language code as a parameter and set params based on it
        // 'language': languageCode,
        // 'model': languageCode == 'en' ? 'nova-3' : 'nova-2',
      },
    );

    final channel = IOWebSocketChannel.connect(
      uri,
      headers: {"Authorization": "Token $key"},
    );

    return channel;
  }
}
