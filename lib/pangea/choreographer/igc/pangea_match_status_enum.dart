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

  double get opacity => switch (this) {
    open => 0.8,
    _ => 0.4,
  };
}
