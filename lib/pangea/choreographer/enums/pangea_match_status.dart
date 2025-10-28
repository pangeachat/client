enum PangeaMatchStatus {
  open,
  ignored,
  accepted,
  automatic,
  unknown;

  static PangeaMatchStatus fromString(String status) {
    final String lastPart = status.toString().split('.').last;
    switch (lastPart) {
      case 'open':
        return PangeaMatchStatus.open;
      case 'ignored':
        return PangeaMatchStatus.ignored;
      case 'accepted':
        return PangeaMatchStatus.accepted;
      case 'automatic':
        return PangeaMatchStatus.automatic;
      default:
        return PangeaMatchStatus.unknown;
    }
  }
}
