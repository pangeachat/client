import 'package:flutter/material.dart';

/// A horizontally scrolling row of single-select filter pills — the chat
/// list's and the Courses hub's (#9207), so the two look and act alike.
class FilterPillRow<T> extends StatelessWidget {
  final String semanticsLabel;
  final List<T> filters;
  final T selected;
  final ValueChanged<T> onSelected;
  final String Function(T filter) labelOf;
  final String Function(T filter) tooltipOf;
  final EdgeInsetsGeometry padding;

  const FilterPillRow({
    super.key,
    required this.semanticsLabel,
    required this.filters,
    required this.selected,
    required this.onSelected,
    required this.labelOf,
    required this.tooltipOf,
    this.padding = const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 4.0),
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel,
      container: true,
      child: Align(
        alignment: Alignment.centerLeft,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: padding,
          child: Row(
            spacing: 8.0,
            children: filters.map((filter) {
              return FilterChip(
                selected: filter == selected,
                onSelected: (_) => onSelected(filter),
                label: Text(labelOf(filter)),
                tooltip: tooltipOf(filter),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
