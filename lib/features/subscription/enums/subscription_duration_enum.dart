import 'package:fluffychat/l10n/l10n.dart';

enum SubscriptionDuration {
  month,
  year;

  String cardTitle(L10n l10n) => switch (this) {
    SubscriptionDuration.month => l10n.mostPopular,
    SubscriptionDuration.year => l10n.mostSavings,
  };

  String copy(L10n l10n) => switch (this) {
    SubscriptionDuration.month => l10n.monthlySubscription,
    SubscriptionDuration.year => l10n.yearlySubscription,
  };

  String periodPriceDisplay(L10n l10n, String price) => switch (this) {
    SubscriptionDuration.month => l10n.pricePerMonth(price),
    SubscriptionDuration.year => l10n.pricePerYear(price),
  };
}
