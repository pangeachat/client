enum PangeaMatchStatusEnum {
  open,
  ignored,
  accepted,
  automatic,
  unknown;

  static PangeaMatchStatusEnum fromString(String status) {
    final String lastPart = status.toString().split('.').last;
    switch (lastPart) {
      case 'open':
        return PangeaMatchStatusEnum.open;
      case 'ignored':
        return PangeaMatchStatusEnum.ignored;
      case 'accepted':
        return PangeaMatchStatusEnum.accepted;
      case 'automatic':
        return PangeaMatchStatusEnum.automatic;
      default:
        return PangeaMatchStatusEnum.unknown;
    }
  }
}
