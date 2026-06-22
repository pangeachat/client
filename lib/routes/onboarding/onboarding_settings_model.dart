class OnboardingSettingsModel {
  final bool showedTrialPage;

  const OnboardingSettingsModel({required this.showedTrialPage});

  OnboardingSettingsModel copyWith({bool? showedTrialPage}) =>
      OnboardingSettingsModel(
        showedTrialPage: showedTrialPage ?? this.showedTrialPage,
      );

  Map<String, dynamic> toJson() => {"showed_trial_page": showedTrialPage};

  factory OnboardingSettingsModel.fromJson(Map<String, dynamic> json) =>
      OnboardingSettingsModel(
        showedTrialPage: json["showed_trial_page"] ?? false,
      );
}
