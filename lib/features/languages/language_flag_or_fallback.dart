import 'package:flutter/material.dart';

import 'package:fluffychat/features/languages/language_model.dart';
import 'package:fluffychat/pangea/common/utils/svg_repo.dart';

/// Draws [flag] only when there is a flag to draw: [language] is one we show a
/// flag for at all, and its SVG loaded. Otherwise — a language whose display
/// name is disambiguated by a variant, a missing asset, or a device with no
/// connection — it draws [fallback], the surface's no-flag appearance (#8548).
///
/// Both children are passed fully formed, so the fallback is free to differ in
/// size and shape from the flag: an avatar circle where the flag is a
/// rectangle, nothing at all where an empty box would read as a gap. That is
/// what the flag's own [NetworkSvg.errorWidget] cannot do — it only replaces
/// the image, leaving the sizing and spacing its caller wrapped it in.
///
/// A failed fetch is remembered for the session ([SvgRepo]), so the surface
/// settles on its fallback instead of retrying and flickering.
class LanguageFlagOrFallback extends StatefulWidget {
  final LanguageModel language;
  final Widget flag;
  final Widget fallback;

  const LanguageFlagOrFallback({
    required this.language,
    required this.flag,
    required this.fallback,
    super.key,
  });

  @override
  State<LanguageFlagOrFallback> createState() => _LanguageFlagOrFallbackState();
}

class _LanguageFlagOrFallbackState extends State<LanguageFlagOrFallback> {
  /// Whether the flag can be drawn — null while its fetch is still in flight,
  /// where [LanguageFlagOrFallback.flag] holds the space with its own
  /// placeholder rather than the layout jumping once it lands.
  bool? _hasFlag;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant LanguageFlagOrFallback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.language != widget.language) _resolve();
  }

  /// Settles synchronously whenever the answer is already known — the language
  /// has no flag, or this URL was fetched earlier in the session — so a row
  /// scrolling back into view doesn't flash the flag's placeholder again.
  void _resolve() {
    final language = widget.language;
    if (!language.shouldShowFlag) {
      _hasFlag = false;
      return;
    }

    final url = language.svgUrl.toString();
    final settled = SvgRepo.peek(url);
    _hasFlag = settled == null ? null : !settled.isError;
    if (settled == null) _load(url);
  }

  Future<void> _load(String url) async {
    final result = await SvgRepo.get(url);
    if (!mounted || url != widget.language.svgUrl.toString()) return;
    setState(() => _hasFlag = !result.isError);
  }

  @override
  Widget build(BuildContext context) =>
      _hasFlag == false ? widget.fallback : widget.flag;
}
