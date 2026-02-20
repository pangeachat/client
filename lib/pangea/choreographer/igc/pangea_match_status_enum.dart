enum PangeaMatchStatusEnum {
  open,
  accepted,
  automatic,
  viewed,
  undo;

  bool get isOpen => switch (this) {
    open => true,
    viewed => true,
    undo => true,
    _ => false,
  };
}
