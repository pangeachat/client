import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/enum/progress_indicators_enum.dart';
import 'package:fluffychat/pangea/models/analytics/construct_list_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/l10n.dart';

class AnalyticsPopup extends StatelessWidget {
  final ProgressIndicatorEnum indicator;
  final ConstructListModel constructsModel;

  const AnalyticsPopup({
    required this.indicator,
    required this.constructsModel,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 400,
          maxHeight: 600,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20.0),
          child: Scaffold(
            appBar: AppBar(
              title: Text(indicator.tooltip(context)),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: Navigator.of(context).pop,
              ),
            ),
            body: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: constructsModel.constructs.isEmpty
                  ? Center(
                      child: Text(L10n.of(context)!.noDataFound),
                    )
                  : ListView.builder(
                      itemCount: constructsModel.constructs.length,
                      itemBuilder: (context, index) {
                        return Tooltip(
                          message:
                              "${constructsModel.constructs[index].points} / ${constructsModel.maxXPPerLemma}",
                          child: ListTile(
                            onTap: () {},
                            title: Text(
                              constructsModel.constructs[index].lemma,
                            ),
                            subtitle: LinearProgressIndicator(
                              value: constructsModel.constructs[index].points /
                                  constructsModel.maxXPPerLemma,
                              minHeight: 20,
                              borderRadius: const BorderRadius.all(
                                Radius.circular(AppConfig.borderRadius),
                              ),
                              color: indicator.color(context),
                            ),
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 20),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
