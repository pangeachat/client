/// A step of the learner's journey that the engagement system reads to choose
/// an onboarding nudge (engagement analytics.instructions.md,
/// Journey-checklist state). [key] is the step's name in the checklist.
enum JourneyStep {
  completePractice('complete_practice'),
  viewSubscriptionPage('view_subscription_page'),
  acceptTranslation('accept_translation'),
  closeTrialPage('close_trial_page');

  const JourneyStep(this.key);

  final String key;
}
