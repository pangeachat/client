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

    return Padding(
      padding: EdgeInsetsGeometry.symmetric(vertical: 4),
      child: Material(
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
      ),
    );
  }
}

/// The search field a `DropdownButtonFormField2` menu shows above its items.
///
/// Swallows pointer input until the menu's open transition has finished. The
/// menu opens under the cursor that just clicked the dropdown button, so the
/// second click of a double-click lands on this field while the menu is still
/// animating. On web that tap desynchronises the browser's DOM focus from
/// Flutter's: the field keeps framework focus and paints a caret, but the
/// browser has moved DOM focus to the flutter view, so every keystroke is
/// swallowed and no later click recovers it (client #8973).
class DropdownSearchField extends StatefulWidget {
  final TextEditingController controller;
  final String labelText;

  const DropdownSearchField({
    super.key,
    required this.controller,
    required this.labelText,
  });

  @override
  State<DropdownSearchField> createState() => _DropdownSearchFieldState();
}

class _DropdownSearchFieldState extends State<DropdownSearchField> {
  Animation<double>? _transition;
  bool _opened = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animation = ModalRoute.of(context)?.animation;
    if (animation == _transition) return;
    _transition?.removeStatusListener(_onTransition);
    _transition = animation;
    _opened =
        animation == null || animation.status == AnimationStatus.completed;
    animation?.addStatusListener(_onTransition);
  }

  @override
  void dispose() {
    _transition?.removeStatusListener(_onTransition);
    super.dispose();
  }

  void _onTransition(AnimationStatus status) {
    final opened = status == AnimationStatus.completed;
    if (opened == _opened) return;
    setState(() => _opened = opened);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: AbsorbPointer(
        absorbing: !_opened,
        child: PangeaSearchBar(
          labelText: widget.labelText,
          autofocus: true,
          controller: widget.controller,
        ),
      ),
    );
  }
}
