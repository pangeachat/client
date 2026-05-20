abstract class ActivitySessionStateController {
  String? get descriptionText;

  bool isRoleSelected(String id);

  bool isRoleShimmering(String id);

  bool canSelectRole(String id);

  void selectRole(String id);
}
