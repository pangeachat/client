enum PangeaMatchStatusEnum {
  open,
  accepted,
  automatic,
  viewed,
  undo;

  /// Whether the match is still unresolved, so the card shows its choices
  /// rather than the diff. An undone match is open again: undo restores the
  /// choices. See writing-assistance.instructions.md.
  bool get isOpen => switch (this) {
    open => true,
    viewed => true,
    undo => true,
    _ => false,
  };

  double get underlineOpacity => switch (this) {
    open => 0.8,
    _ => 0.25,
  };

  double get igcButtonOpacity => switch (this) {
    open => 0.8,
    accepted => 0.8,
    automatic => 0.8,
    _ => 0.25,
  };
}
