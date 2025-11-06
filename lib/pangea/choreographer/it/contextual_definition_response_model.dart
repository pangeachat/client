class ContextualDefinitionResponseModel {
  final String text;

  const ContextualDefinitionResponseModel({required this.text});

  factory ContextualDefinitionResponseModel.fromJson(
    Map<String, dynamic> json,
  ) =>
      ContextualDefinitionResponseModel(text: json["response"]);
}
