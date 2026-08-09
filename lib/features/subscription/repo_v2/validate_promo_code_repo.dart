import 'package:http/http.dart';

import 'package:fluffychat/features/subscription/repo_v2/validate_promo_code_request.dart';
import 'package:fluffychat/features/subscription/repo_v2/validate_promo_code_response.dart';
import 'package:fluffychat/pangea/common/network/requests.dart';
import 'package:fluffychat/pangea/common/network/urls.dart';
import 'package:fluffychat/pangea/common/utils/base_repo.dart';
import 'package:fluffychat/pangea/common/utils/memory_repo_cache.dart';

class ValidatePromoCodeRepo
    extends BaseRepo<ValidatePromoCodeRequest, ValidatePromoCodeResponse> {
  ValidatePromoCodeRepo._internal()
    : super(
        cache: MemoryRepoCache(),
        responseFromJson: ValidatePromoCodeResponse.fromJson,
        cacheDuration: const Duration(minutes: 10),
      );

  static final ValidatePromoCodeRepo _instance =
      ValidatePromoCodeRepo._internal();

  static ValidatePromoCodeRepo get instance => _instance;

  @override
  Future<Response> fetch(Requests req, ValidatePromoCodeRequest request) {
    final duration = request.duration;
    final uri = Uri.parse(PApiUrls.validatePromoCode).replace(
      queryParameters: {
        'code': request.code,
        if (duration != null) 'duration': duration.name,
      },
    );
    return req.get(url: uri.toString());
  }
}
