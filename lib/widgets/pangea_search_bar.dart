import 'package:flutter/material.dart';

class PangeaSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final Function(String)? onChanged;
  final String? labelText;
  final Widget? suffixIcon;
  final bool autofocus;
  final FocusNode? focusNode;

  const PangeaSearchBar({
    super.key,
    required this.controller,
    this.onChanged,
    this.labelText,
    this.suffixIcon,
    this.autofocus = false,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(99),
      color: theme.colorScheme.surface,
      child: Semantics(
        container: true,
        child: TextField(
          controller: controller,
          autofocus: autofocus,
          focusNode: focusNode,
          onChanged: onChanged,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: theme.colorScheme.surface,
            labelText: labelText,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: suffixIcon,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(99),
              borderSide: BorderSide(
                color: theme.colorScheme.surfaceContainerHigh,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
