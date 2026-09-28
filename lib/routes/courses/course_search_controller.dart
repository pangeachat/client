import 'dart:async';

import 'package:flutter/material.dart';

import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/pangea/common/utils/async_state.dart';
import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/pangea/common/utils/search_text.dart';
import 'package:fluffychat/pangea/common/utils/web_search_focus_keeper.dart';
import 'package:fluffychat/routes/courses/add_course_tile_content.dart';

typedef CoursesLoader<T> = ValueNotifier<AsyncState<List<T>>>;

abstract class CourseSearchController<T> {
  final String Function(T) getCourseName;
  CourseSearchController({required this.getCourseName});

  List<T> _loadedCourses = [];
  final CoursesLoader<T> _filteredCoursesLoader = CoursesLoader(AsyncLoading());

  final ValueNotifier<LanguageModel?> _targetLanguageFilter = ValueNotifier(
    null,
  );

  final TextEditingController _searchController = TextEditingController();
  final ValueNotifier<bool> _searchingNotifier = ValueNotifier(false);
  final FocusNode _focusNode = FocusNode();
  late final WebSearchFocusKeeper _focusKeeper = WebSearchFocusKeeper(
    focusNode: _focusNode,
    isSearchOpen: () => !_disposed && _searchingNotifier.value,
  );
  Timer? _debounce;

  final ValueNotifier<bool> _loadingMore = ValueNotifier(false);

  final ScrollController _scrollController = ScrollController();

  int _loadGeneration = 0;
  bool _fullyLoaded = false;
  bool _disposed = false;

  void initCourseSearch() {
    _searchController.addListener(_onSearch);
    loadMore();
  }

  void disposeCourseSearch() {
    _disposed = true;
    _focusKeeper.disarm();
    _filteredCoursesLoader.dispose();
    _searchController.removeListener(_onSearch);
    _scrollController.dispose();
    _searchController.dispose();
    _searchingNotifier.dispose();
    _focusNode.dispose();
    _debounce?.cancel();
    _targetLanguageFilter.dispose();
    _loadingMore.dispose();
  }

  ScrollController get scrollController => _scrollController;
  ValueNotifier<bool> get searchingNotifier => _searchingNotifier;
  TextEditingController get searchController => _searchController;
  FocusNode get focusNode => _focusNode;

  ValueNotifier<LanguageModel?> get targetLanguageFilter =>
      _targetLanguageFilter;

  ValueNotifier<AsyncState<List<T>>> get filteredCoursesLoader =>
      _filteredCoursesLoader;

  ValueNotifier<bool> get loadingMore => _loadingMore;

  bool get fullyLoaded => _fullyLoaded;
  List<T> get loadedCourses => _loadedCourses;
  int get loadGeneration => _loadGeneration;
  bool get disposed => _disposed;

  List<T> get filteredCourses {
    final query = SearchTextUtil.normalize(_searchController.text.trim());
    if (query.isEmpty) return [..._loadedCourses];

    final filtered = _loadedCourses.where((c) {
      final normalizedTitle = SearchTextUtil.normalize(getCourseName(c));
      return normalizedTitle.contains(query);
    }).toList();

    filtered.sort((a, b) {
      final normalizedA = SearchTextUtil.normalize(getCourseName(a));
      final normalizedB = SearchTextUtil.normalize(getCourseName(b));
      final aStarts = normalizedA.startsWith(query);
      final bStarts = normalizedB.startsWith(query);
      if (aStarts && !bStarts) return -1;
      if (!aStarts && bStarts) return 1;
      return 0;
    });

    return filtered;
  }

  void setLoadedCourses(List<T> courses) => _loadedCourses = courses;

  void setFullyLoaded(bool value) => _fullyLoaded = value;

  void setTargetLanguageFilter(LanguageModel? language) {
    if (_targetLanguageFilter.value == language) return;
    _targetLanguageFilter.value = language;
    _loadGeneration++;
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }

    _reset();
    loadMore();
  }

  void stopSearching() {
    _focusKeeper.disarm();
    _searchingNotifier.value = false;
    _focusNode.unfocus();
    _searchController.clear();
    setFilteredCourses(AsyncLoaded(_loadedCourses));
  }

  void startSearching() {
    _searchingNotifier.value = true;
    // TextField.autofocus no-ops when the tapped toggle still holds focus, so
    // request focus once the field is mounted (same as PangeaChatListSearchField).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed) return;
      _focusNode.requestFocus();
      _focusKeeper.arm();
    });
    _searchController.clear();
    setFilteredCourses(AsyncLoaded(_loadedCourses));
  }

  void _onSearch() {
    _debounce?.cancel();
    _debounce = Timer(Duration(milliseconds: 250), () {
      setFilteredCourses(AsyncLoaded(filteredCourses));
      _debounce?.cancel();
    });
  }

  void reset();

  void _reset() {
    reset();
    _fullyLoaded = false;
    _loadingMore.value = false;
    _loadedCourses.clear();
    setFilteredCourses(AsyncLoading());
  }

  void setFilteredCourses(AsyncState<List<T>> state) {
    if (_disposed) return;
    if (state is AsyncLoaded && (state as AsyncLoaded).value.isEmpty) {
      loadMore();
    }
    _filteredCoursesLoader.value = state;
  }

  AddCourseTileContent courseToTileContent(T course);

  void onSelect(T course, BuildContext context);

  void onNotFound(BuildContext context);

  Future<void> loadMore() async {
    if (_fullyLoaded || _loadingMore.value) return;
    final int generation = _loadGeneration;
    _loadingMore.value = true;
    try {
      await fetchAndAppend(generation);
    } finally {
      if (!_disposed && _loadGeneration == generation) {
        _loadingMore.value = false;
      }
    }

    if (_loadGeneration == generation &&
        _loadedCourses.isEmpty &&
        _filteredCoursesLoader.value is AsyncLoaded) {
      ErrorHandler.logError(
        e: "No courses found",
        data: {'filter': _targetLanguageFilter.value?.toJson()},
      );
    }
  }

  Future<void> fetchAndAppend(int generation);
}
