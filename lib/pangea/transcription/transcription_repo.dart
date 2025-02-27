import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:http/http.dart';

class TranscriptionRepo {

  openSession() async {

final Requests req = Requests(
      choreoApiKey: Environment.choreoApiKey,
      accessToken: PApiUrls.realtimeSessionAuth,
    );

    final Response res = await req.post(
      url: PApiUrls.topicList,
      body: {},
    );
  }
}