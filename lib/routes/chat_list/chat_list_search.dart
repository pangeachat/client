import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// The chat list's search: the query field's text and focus, and whether the
/// list is filtered by it. Search filters the learner's own rooms only; it
/// makes no server request (#9431).
///
/// When a toggle drives the field ([searchFieldVisibility], the chats panel
/// header's search icon), closing the field ends the search, whichever control
/// closed it, so the list goes back to every chat (#9449).
mixin ChatListSearch<T extends StatefulWidget> on State<T> {
  /// The toggle that shows and hides the search field, when one drives it.
  /// Null when the field is always shown.
  ValueListenable<bool>? get searchFieldVisibility;

  bool isSearchMode = false;

  final TextEditingController searchController = TextEditingController();
  final FocusNode searchFocusNode = FocusNode();

  void onSearchEnter(String text) {
    if (text.isEmpty) {
      cancelSearch(unfocus: false);
      return;
    }

    setState(() {
      isSearchMode = true;
    });
  }

  void cancelSearch({bool unfocus = true}) {
    setState(() {
      searchController.clear();
      isSearchMode = false;
    });
    if (unfocus) searchFocusNode.unfocus();
  }

  /// Called when [searchFieldVisibility] shows the field.
  @protected
  void onSearchFieldOpened() {}

  void _onSearchFieldVisibilityChanged() {
    if (searchFieldVisibility?.value == true) {
      onSearchFieldOpened();
      return;
    }
    if (isSearchMode || searchController.text.isNotEmpty) cancelSearch();
  }

  @override
  void initState() {
    super.initState();
    searchFieldVisibility?.addListener(_onSearchFieldVisibilityChanged);
  }

  @override
  void dispose() {
    searchFieldVisibility?.removeListener(_onSearchFieldVisibilityChanged);
    super.dispose();
  }
}
