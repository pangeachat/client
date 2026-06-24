class WidgetBoundaries {
  final double left;
  final double right;
  final double top;
  final double bottom;

  const WidgetBoundaries({
    required this.left,
    required this.right,
    required this.top,
    required this.bottom,
  });

  static WidgetBoundaries get defaultBoundaries =>
      WidgetBoundaries(top: 0, bottom: 0, left: 0, right: 0);

  Map<String, dynamic> toJson() => {
    "left": left,
    "right": right,
    "top": top,
    "bottom": bottom,
  };
}
