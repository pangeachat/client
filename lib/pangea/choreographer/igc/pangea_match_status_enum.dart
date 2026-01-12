enum PangeaMatchStatusEnum {
  open,
  ignored,
  accepted,
  automatic,
  undo,
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
      case 'undo':
        return PangeaMatchStatusEnum.undo;
      default:
        return PangeaMatchStatusEnum.unknown;
    }
  }
}
