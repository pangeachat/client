abstract class TokenParam {
  const TokenParam();

  bool get isPushed => false;

  TokenParam? get poppedParam => null;

  String build();
}
