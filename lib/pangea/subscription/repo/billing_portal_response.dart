class BillingPortalResponse {
  final String url;

  const BillingPortalResponse({required this.url});

  factory BillingPortalResponse.fromJson(Map<String, dynamic> json) =>
      BillingPortalResponse(url: json["url"]);

  Map<String, dynamic> toJson() => {"url": url};
}
