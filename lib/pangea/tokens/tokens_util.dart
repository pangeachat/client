import 'package:characters/characters.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/pangea/events/event_wrappers/pangea_message_event.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_model.dart';
import 'package:fluffychat/pangea/events/models/pangea_token_text_model.dart';
import 'package:fluffychat/widgets/matrix.dart';

class _TokenPositionCacheItem {
  final List<TokenPosition> positions;
  final DateTime timestamp;

  _TokenPositionCacheItem(this.positions, this.timestamp);
}

class _NewTokenCacheItem {
  final Set<PangeaTokenText> tokens;
  final DateTime timestamp;

  _NewTokenCacheItem(this.tokens, this.timestamp);
}

class TokenPosition {
  final PangeaToken? token;
  final int startIndex;
  final int endIndex;

  const TokenPosition({
    this.token,
    required this.startIndex,
    required this.endIndex,
  });

  Map<String, dynamic> toJson() => {
    'token': token?.toJson(),
    'startIndex': startIndex,
    'endIndex': endIndex,
  };
}

class TokensUtil {
  TokensUtil._();
  static final TokensUtil instance = TokensUtil._();

  /// A cache of calculated adjacent token positions
  final Map<String, _TokenPositionCacheItem> _tokenPositionCache = {};
  final Map<String, _NewTokenCacheItem> _newTokenCache = {};
  PangeaTokenText? lastCollected;

  static const Duration _cacheDuration = Duration(minutes: 1);

  Set<PangeaTokenText>? _getCachedNewTokens(String cacheKey) {
    final cacheItem = _newTokenCache[cacheKey];
    if (cacheItem == null) return null;
    if (cacheItem.timestamp.isBefore(DateTime.now().subtract(_cacheDuration))) {
      _newTokenCache.remove(cacheKey);
      return null;
    }

    return cacheItem.tokens;
  }

  void _setCachedNewTokens(String cacheKey, Set<PangeaTokenText> tokens) {
    _newTokenCache[cacheKey] = _NewTokenCacheItem(tokens, DateTime.now());
  }

  Set<PangeaTokenText> getNewTokens(
    String cacheKey,
    List<PangeaToken> tokens,
    String tokensLangCode, {
    int? maxTokens,
  }) {
    if (MatrixState
        .pangeaController
        .matrixState
        .analyticsDataService
        .isInitializing) {
      return {};
    }

    final messageInUserL2 =
        tokensLangCode.split('-').first ==
        MatrixState.pangeaController.userController.userL2?.langCodeShort;

    final cached = _getCachedNewTokens(cacheKey);
    if (cached != null) {
      if (!messageInUserL2) {
        _newTokenCache.remove(cacheKey);
        return {};
      }
      return cached;
    }

    if (!messageInUserL2) return {};

    final Set<PangeaTokenText> newTokens = {};
    final analyticsService =
        MatrixState.pangeaController.matrixState.analyticsDataService;

    for (final token in tokens) {
      final cId = token.vocabConstructID;
      if (!token.lemma.saveVocab || !cId.isContentWord) {
        continue;
      }

      if (analyticsService.hasUsedConstruct(cId) ||
          analyticsService.isConstructBlocked(cId)) {
        continue;
      }

      if (newTokens.any((t) => t == token.text)) continue;

      newTokens.add(token.text);
      if (maxTokens != null && newTokens.length >= maxTokens) break;
    }

    _setCachedNewTokens(cacheKey, newTokens);
    return newTokens;
  }

  Set<PangeaTokenText> getNewTokensByEvent(PangeaMessageEvent event) {
    if (!event.eventId.isValidMatrixId ||
        (MatrixState.pangeaController.subscriptionController.isSubscribed ==
            false) ||
        MatrixState
            .pangeaController
            .matrixState
            .analyticsDataService
            .isInitializing) {
      return {};
    }

    final messageInUserL2 =
        event.messageDisplayLangCode.split("-")[0] ==
        MatrixState.pangeaController.userController.userL2?.langCodeShort;

    final cached = _getCachedNewTokens(event.eventId);
    if (cached != null) {
      if (!messageInUserL2) {
        _newTokenCache.remove(event.eventId);
        return {};
      }
      return cached;
    }

    final tokens = event.messageDisplayRepresentation?.tokens;
    if (!messageInUserL2 || tokens == null || tokens.isEmpty) {
      return {};
    }

    return getNewTokens(
      event.eventId,
      tokens,
      event.messageDisplayLangCode,
      maxTokens: 3,
    );
  }

  bool isNewTokenByEvent(PangeaToken token, PangeaMessageEvent event) {
    final newTokens = getNewTokensByEvent(event);
    return newTokens.any((t) => t == token.text);
  }

  void clearNewTokenCache() {
    _newTokenCache.clear();
  }

  void collectToken(String cachedKey, PangeaTokenText token) {
    _newTokenCache[cachedKey]?.tokens.remove(token);
    lastCollected = token;
  }

  bool isRecentlyCollected(PangeaTokenText token) => lastCollected == token;

  void clearRecentlyCollected() => lastCollected = null;

  List<TokenPosition>? _getCachedTokenPositions(String cacheKey) {
    final cacheItem = _tokenPositionCache[cacheKey];
    if (cacheItem == null) return null;
    if (cacheItem.timestamp.isBefore(DateTime.now().subtract(_cacheDuration))) {
      _tokenPositionCache.remove(cacheKey);
      return null;
    }

    return cacheItem.positions;
  }

  void _setCachedTokenPositions(
    String cacheKey,
    List<TokenPosition> positions,
  ) {
    _tokenPositionCache[cacheKey] = _TokenPositionCacheItem(
      positions,
      DateTime.now(),
    );
  }

  /// Given a list of tokens, returns a list of positions for tokens and adjacent punctuation
  /// This list may include gaps in the actual message for non-token elements,
  /// so should not be used to fully reconstruct the original message.
  List<TokenPosition> getAdjacentTokenPositions(
    String eventID,
    List<PangeaToken> tokens,
  ) {
    final cached = _getCachedTokenPositions(eventID);
    if (cached != null) {
      return cached;
    }

    final List<TokenPosition> positions = [];
    for (int i = 0; i < tokens.length; i++) {
      final PangeaToken token = tokens[i];

      PangeaToken? currentToken = token;
      PangeaToken? nextToken = i < tokens.length - 1 ? tokens[i + 1] : null;

      final isPunct = token.pos == 'PUNCT';
      final nextIsPunct = nextToken?.pos == 'PUNCT';

      final int startIndex = i;
      if (isPunct || nextIsPunct) {
        bool punctPickup = true;
        while (nextToken != null &&
            currentToken?.end == nextToken.start &&
            punctPickup) {
          i++;
          currentToken = nextToken;
          nextToken = i < tokens.length - 1 ? tokens[i + 1] : null;
          punctPickup = nextToken?.pos == 'PUNCT';
        }
      }

      final adjacentTokens = tokens.sublist(startIndex, i + 1);
      if (adjacentTokens.every((t) => t.pos == 'PUNCT')) {
        continue;
      }

      final position = TokenPosition(
        token: adjacentTokens.firstWhere((t) => t.pos != 'PUNCT'),
        startIndex: startIndex,
        endIndex: i,
      );
      positions.add(position);
    }

    _setCachedTokenPositions(eventID, positions);
    return positions;
  }

  /// Given a list of tokens and the original transcript, reconstructs the
  /// message as a sequence of positions — one per token, plus gap positions
  /// for any non-token text in between (e.g. whitespace).
  ///
  /// Backend tokenizers (spaCy, LLM, Google, Whisper) produce `token.text.offset`
  /// in **Unicode code-point units** (Python `len()` semantics). The returned
  /// `TokenPosition` indices are in **Dart grapheme-cluster units**, matching
  /// `String.characters` — which is what the renderer slices by. These units
  /// differ for Indic scripts with matras, many emoji, and combining marks.
  List<TokenPosition> getGlobalTokenPositions(
    List<PangeaToken> tokens, {
    required String transcript,
  }) {
    final List<TokenPosition> tokenPositions = [];
    final _GraphemeIndex index = _GraphemeIndex.fromText(transcript);

    // Pre-translate each token's code-point range into grapheme indices.
    final int n = tokens.length;
    final List<int> gStart = List.filled(n, 0);
    final List<int> gEnd = List.filled(n, 0);
    for (var i = 0; i < n; i++) {
      final t = tokens[i];
      final int cpStart = t.text.offset;
      // `content.runes.length` is the code-point length (matches the backend's
      // `len()` semantics); we intentionally ignore `t.text.length` here
      // because `PangeaTokenText.fromJson` stores it as a grapheme count and
      // mixing units is the root of issue #1963.
      final int cpEnd = cpStart + t.text.content.runes.length;
      gStart[i] = index.graphemeStartOfCodepoint(cpStart);
      gEnd[i] = index.graphemeEndOfCodepoint(cpEnd);
    }

    int tokenPointer = 0;
    int globalPointer = 0;

    while (tokenPointer < n) {
      int endIndex = tokenPointer;
      PangeaToken token = tokens[tokenPointer];

      if (gStart[tokenPointer] > globalPointer) {
        // Gap between the previous token and this one (usually whitespace).
        tokenPositions.add(
          TokenPosition(
            startIndex: globalPointer,
            endIndex: gStart[tokenPointer],
          ),
        );
        globalPointer = gStart[tokenPointer];
      }

      // Merge this token with an adjacent punctuation token if either side is
      // PUNCT and there is no gap between them in grapheme space.
      while (endIndex < n - 1) {
        final PangeaToken currentToken = tokens[endIndex];
        final PangeaToken nextToken = tokens[endIndex + 1];

        final currentIsPunct =
            currentToken.pos == 'PUNCT' &&
            currentToken.text.content.trim().isNotEmpty;
        final nextIsPunct =
            nextToken.pos == 'PUNCT' &&
            nextToken.text.content.trim().isNotEmpty;

        if (gEnd[endIndex] != gStart[endIndex + 1]) {
          break;
        }

        if ((currentIsPunct && nextIsPunct) ||
            (currentIsPunct && nextToken.text.content.trim().isNotEmpty) ||
            (nextIsPunct && currentToken.text.content.trim().isNotEmpty)) {
          if (token.pos == 'PUNCT' && !nextIsPunct) {
            token = nextToken;
          }
          endIndex++;
        } else {
          break;
        }
      }

      tokenPositions.add(
        TokenPosition(
          token: token,
          startIndex: gStart[tokenPointer],
          endIndex: gEnd[endIndex],
        ),
      );

      tokenPointer = tokenPointer + (endIndex - tokenPointer) + 1;
      globalPointer = gEnd[endIndex];
    }

    return tokenPositions;
  }
}

/// Maps code-point offsets (the unit used by backend tokenizers) to
/// grapheme-cluster offsets (the unit used by Dart's `String.characters`).
///
/// Built once per transcript; subsequent lookups are O(log n).
class _GraphemeIndex {
  /// `_starts[i]` is the code-point index at which grapheme cluster `i`
  /// begins. Sorted ascending; length equals the grapheme count.
  final List<int> _starts;
  final int _codepointCount;

  _GraphemeIndex._(this._starts, this._codepointCount);

  factory _GraphemeIndex.fromText(String text) {
    final List<int> starts = [];
    int cp = 0;
    for (final g in text.characters) {
      starts.add(cp);
      cp += g.runes.length;
    }
    return _GraphemeIndex._(starts, cp);
  }

  int get graphemeCount => _starts.length;

  /// Grapheme index containing code-point position `cp`. If `cp` falls inside
  /// a multi-codepoint grapheme, returns that grapheme's index.
  int graphemeStartOfCodepoint(int cp) {
    if (cp <= 0) return 0;
    if (cp >= _codepointCount) return _starts.length;
    // Largest i with _starts[i] <= cp.
    int lo = 0, hi = _starts.length - 1;
    while (lo < hi) {
      final int mid = (lo + hi + 1) >> 1;
      if (_starts[mid] <= cp) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// Grapheme index (exclusive end) for a range that ends at code-point `cp`.
  /// An end that falls inside a grapheme rounds up to include that grapheme.
  int graphemeEndOfCodepoint(int cp) {
    if (cp <= 0) return 0;
    if (cp >= _codepointCount) return _starts.length;
    // Smallest i with _starts[i] >= cp.
    int lo = 0, hi = _starts.length;
    while (lo < hi) {
      final int mid = (lo + hi) >> 1;
      if (_starts[mid] < cp) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }
}
