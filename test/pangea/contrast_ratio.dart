import 'dart:math';

import 'package:flutter/material.dart';

/// WCAG 1.4.11 asks 3:1 of a graphic the user has to read — a star whose fill
/// is the state, a progress bar whose extent is the reading.
const double minGraphicRatio = 3.0;

double _relativeLuminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

/// The WCAG contrast ratio between two opaque colours, 1.0–21.0.
double contrastRatio(Color a, Color b) {
  final la = _relativeLuminance(a);
  final lb = _relativeLuminance(b);
  return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
}
