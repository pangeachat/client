import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:dropdown_button2/dropdown_button2.dart';

class CoursePlanFilter<T> extends StatefulWidget {
  final T? value;
  final List<T> items;

  final void Function(T?) onChanged;
  final String defaultName;
  final Widget Function(T) displayname;
  final Widget Function(T)? selectedItemBuilder;

  final bool enableSearch;
  final bool Function(DropdownMenuItem<T>, String)? searchMatchFn;

  const CoursePlanFilter({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.defaultName,
    required this.displayname,
    this.selectedItemBuilder,
    this.enableSearch = false,
    this.searchMatchFn,
  });

  @override
  State<CoursePlanFilter<T>> createState() => CoursePlanFilterState<T>();
}

class CoursePlanFilterState<T> extends State<CoursePlanFilter<T>> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DropdownButtonHideUnderline(
      child: DropdownButton2<T>(
        customButton: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(40.0),
            color: theme.colorScheme.surfaceContainerHighest,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              widget.value != null
                  ? (widget.selectedItemBuilder != null
                        ? widget.selectedItemBuilder!(widget.value as T)
                        : widget.displayname(widget.value as T))
                  : Text(
                      widget.defaultName,
                      style: DefaultTextStyle.of(context).style,
                    ),
              const Icon(Icons.arrow_drop_down),
            ],
          ),
        ),
        value: widget.value,
        items: [null, ...widget.items]
            .map(
              (item) => DropdownMenuItem(
                value: item,
                child: Container(
                  color: item == widget.value
                      ? Theme.of(context).colorScheme.primary.withAlpha(20)
                      : Colors.transparent,
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 12,
                  ),
                  child: item != null
                      ? widget.displayname(item)
                      : Row(
                          children: [
                            Text(
                              widget.defaultName,
                              style: DefaultTextStyle.of(context).style,
                            ),
                          ],
                        ),
                ),
              ),
            )
            .toList(),
        onChanged: widget.onChanged,
        buttonStyleData: ButtonStyleData(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(40)),
        ),
        dropdownStyleData: DropdownStyleData(
          elevation: 8,
          maxHeight: kIsWeb ? 500 : 300,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: theme.colorScheme.surfaceContainerHigh,
          ),
        ),
        menuItemStyleData: const MenuItemStyleData(padding: EdgeInsets.zero),
        dropdownSearchData: widget.enableSearch
            ? DropdownSearchData(
                searchController: _searchController,
                searchInnerWidgetHeight: 50,
                searchInnerWidget: Material(
                  elevation: 4,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(14),
                    topRight: Radius.circular(14),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: TextField(
                      autofocus: true,
                      controller: _searchController,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                  ),
                ),
                searchMatchFn: widget.searchMatchFn,
              )
            : null,
        onMenuStateChange: (isOpen) {
          if (!isOpen) _searchController.clear();
        },
      ),
    );
  }
}
