sealed class CheckoutException implements Exception {}

class InvalidRequestCheckoutException extends CheckoutException {}

class NotFoundCheckoutException extends CheckoutException {}

class ConflictCheckoutException extends CheckoutException {}

class StripeCheckoutException extends CheckoutException {}

class ServiceUnavailableCheckoutException extends CheckoutException {}

class UnknownCheckoutException extends CheckoutException {}
