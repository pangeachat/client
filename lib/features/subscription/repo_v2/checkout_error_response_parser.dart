import 'package:http/http.dart';

import 'package:fluffychat/features/subscription/repo_v2/checkout_exceptions.dart';
import 'package:fluffychat/pangea/common/utils/error_response_parser.dart';

class CheckoutErrorResponseParser
    extends ErrorResponseParser<CheckoutException> {
  @override
  CheckoutException parse(Object error) {
    if (error is! Response) {
      return UnknownCheckoutException();
    }

    return switch (error.statusCode) {
      401 => InvalidRequestCheckoutException(),
      404 => NotFoundCheckoutException(),
      409 => ConflictCheckoutException(),
      502 => StripeCheckoutException(),
      503 => ServiceUnavailableCheckoutException(),
      _ => UnknownCheckoutException(),
    };
  }
}
