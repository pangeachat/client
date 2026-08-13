import 'package:flutter/material.dart';

import 'package:flutter_svg/flutter_svg.dart';

import 'package:fluffychat/pangea/common/utils/svg_repo.dart';

/// An SVG fetched over the network, loaded through [SvgRepo].
///
/// Use this instead of `SvgPicture.network`. That constructor lets
/// `vector_graphics` own the fetch, and on a transport failure it leaks the
/// error onto a future nobody listens to — an unhandled zone error per failed
/// load, even though [errorWidget] renders correctly (#8338). It also has no
/// dedupe, so one offline moment on a list of flags fires an event per flag
/// and again on every rebuild.
///
/// [SvgRepo] is the repo layer for these assets: it catches the failure,
/// fetches once per URL per session, and owns the Sentry report.
class NetworkSvg extends StatefulWidget {
  /// URL of the SVG file.
  final String svgUrl;

  /// Applied to the fetched markup before it is rendered. Used by
  /// `CustomizedSvg` to recolor; most callers render the file as-is.
  final String Function(String)? transform;

  /// Identifies what [transform] will produce. A closure is a fresh object on
  /// every build, so it can't be compared to decide whether to re-transform —
  /// callers pass a value-comparable stand-in (the recolor map flattened to a
  /// string) and the SVG is re-read only when that changes.
  final Object? transformKey;

  /// Shown when the SVG can't be loaded.
  final Widget errorWidget;

  /// Shown while the SVG is loading.
  final Widget? placeholder;

  final double? width;
  final double? height;
  final BoxFit? fit;
  final ColorFilter? colorFilter;

  const NetworkSvg({
    super.key,
    required this.svgUrl,
    this.transform,
    this.transformKey,
    this.errorWidget = const SizedBox.shrink(),
    this.placeholder,
    this.width = 24,
    this.height = 24,
    this.fit,
    this.colorFilter,
  });

  @override
  State<NetworkSvg> createState() => _NetworkSvgState();
}

class _NetworkSvgState extends State<NetworkSvg> {
  String? _svgContent;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadSvg();
  }

  @override
  void didUpdateWidget(covariant NetworkSvg oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.svgUrl != widget.svgUrl ||
        oldWidget.transformKey != widget.transformKey) {
      _loadSvg();
    }
  }

  Future<void> _loadSvg() async {
    final url = widget.svgUrl;
    final transformKey = widget.transformKey;
    if (mounted && !_isLoading) {
      setState(() {
        _isLoading = true;
        _hasError = false;
        _svgContent = null;
      });
    }

    final svg = await SvgRepo.get(url);

    // The widget may have been repointed while this was in flight; the load
    // that superseded it owns the state now.
    if (!mounted ||
        url != widget.svgUrl ||
        transformKey != widget.transformKey) {
      return;
    }

    setState(() {
      _isLoading = false;
      _hasError = svg.isError;
      _svgContent = svg.isError
          ? null
          : (widget.transform?.call(svg.asValue!.value) ?? svg.asValue!.value);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return widget.placeholder ??
          SizedBox(width: widget.width, height: widget.height);
    }

    final svgContent = _svgContent;
    if (_hasError || svgContent == null) return widget.errorWidget;

    return SvgPicture(
      SvgStringLoader(svgContent),
      // Content changes at a stable URL (a recolor on theme flip) are picked up
      // by SvgStringLoader's own equality, which VectorGraphic compares.
      key: ValueKey(widget.svgUrl),
      width: widget.width,
      height: widget.height,
      fit: widget.fit ?? BoxFit.contain,
      colorFilter: widget.colorFilter,
      // Markup we fetched but can't parse. Rare, and separate from the fetch
      // failure above, but it should degrade the same way.
      errorBuilder: (_, _, _) => widget.errorWidget,
    );
  }
}
