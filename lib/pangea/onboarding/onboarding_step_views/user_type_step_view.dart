import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/bot/widgets/bot_face_svg.dart';
import 'package:fluffychat/pangea/onboarding/onboarding_steps/user_type_onboarding_step.dart';
import 'package:fluffychat/pangea/onboarding/user_type_enum.dart';

class UserTypeStepView extends StatefulWidget {
  final UserTypeOnboardingStep step;
  final VoidCallback updateEnableNext;
  const UserTypeStepView({
    super.key,
    required this.step,
    required this.updateEnableNext,
  });

  @override
  UserTypeStepViewState createState() => UserTypeStepViewState();
}

class UserTypeStepViewState extends State<UserTypeStepView> {
  late final UserTypeOnboardingStep _step;

  final ValueNotifier<UserType?> _selectedType = ValueNotifier(null);

  @override
  void initState() {
    super.initState();
    _step = widget.step;
    _selectedType.value = _step.userType;
  }

  @override
  void dispose() {
    _selectedType.dispose();
    super.dispose();
  }

  void _setSelectedType(UserType type) {
    _step.setUserType(type);
    _selectedType.value = type;
    widget.updateEnableNext();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      spacing: 12.0,
      mainAxisSize: MainAxisSize.min,
      children: [
        BotFace(expression: BotExpression.idle, useRive: true, width: 140.0),
        Text(
          L10n.of(context).userTypeTitle,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        ValueListenableBuilder(
          valueListenable: _selectedType,
          builder: (context, type, _) => Column(
            spacing: 12.0,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: EdgeInsetsGeometry.symmetric(horizontal: 16.0),
                child: ElevatedButton(
                  onPressed: () => _setSelectedType(UserType.teacher),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: type == UserType.teacher
                        ? theme.colorScheme.primaryContainer
                        : theme.colorScheme.surfaceContainer,
                    foregroundColor: type == UserType.teacher
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.onSurface,
                  ),
                  child: Row(
                    spacing: 8.0,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.school_outlined, size: 24.0),
                      Text(L10n.of(context).teach),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsetsGeometry.symmetric(horizontal: 16.0),
                child: ElevatedButton(
                  onPressed: () => _setSelectedType(UserType.student),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: type == UserType.student
                        ? theme.colorScheme.primaryContainer
                        : theme.colorScheme.surfaceContainer,
                    foregroundColor: type == UserType.student
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.onSurface,
                  ),
                  child: Row(
                    spacing: 8.0,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Symbols.dictionary, size: 24.0),
                      Text(L10n.of(context).learn),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
