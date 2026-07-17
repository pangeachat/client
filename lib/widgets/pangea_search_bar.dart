import 'package:flutter/material.dart';

class PangeaSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final Function(String)? onChanged;
  final String? labelText;
  final Widget? suffixIcon;
  final bool autofocus;
  final FocusNode? focusNode;
  final Function(String)? onSubmitted;
  final bool? enabled;
  final Widget? prefixIcon;

  const PangeaSearchBar({
    super.key,
    required this.controller,
    this.onChanged,
    this.labelText,
    this.suffixIcon,
    this.autofocus = false,
    this.focusNode,
    this.onSubmitted,
    this.enabled,
    this.prefixIcon,
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
          textInputAction: TextInputAction.search,
          controller: controller,
          autofocus: autofocus,
          focusNode: focusNode,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          enabled: enabled,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: theme.colorScheme.surface,
            labelText: labelText,
            prefixIcon: prefixIcon ?? const Icon(Icons.search),
            suffixIcon: suffixIcon,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(99),
              borderSide: BorderSide(
                color: theme.colorScheme.outlineVariant,
                width: 1,
              ),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(99),
              borderSide: BorderSide(
                color: theme.colorScheme.outlineVariant,
                width: 1,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(99),
              borderSide: BorderSide(
                color: theme.colorScheme.primary,
                width: 2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
