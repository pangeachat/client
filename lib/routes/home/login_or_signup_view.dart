import 'package:flutter/material.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:collection/collection.dart';
import 'package:go_router/go_router.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/routes/home/pangea_logo_svg.dart';

class LoginOrSignupView extends StatefulWidget {
  const LoginOrSignupView({super.key});

  @override
  State<LoginOrSignupView> createState() => _LoginOrSignupViewState();
}

class _LoginOrSignupViewState extends State<LoginOrSignupView> {
  static const _mobileRatioBreakpoint = 1.75;

  final CarouselSliderController _carouselController =
      CarouselSliderController();

  int _currentIndex = 0;

  /// Slide 1 carries the brand line inside its image, so it has no headline.
  List<String?> get _labels => [
    null,
    L10n.of(context).explorePlayAndLearn,
    L10n.of(context).conversationFromDayOne,
    L10n.of(context).builtForConnection,
    L10n.of(context).aiWhenYouNeedIt,
    L10n.of(context).practiceTailoredForYou,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    final isMobile = size.height / size.width > _mobileRatioBreakpoint;
    // The wide slide 1 bakes its brand text into the artwork, so it ships in
    // a per-theme variant: dark text for light mode, light text for dark.
    final slide1Suffix = theme.brightness == Brightness.dark
        ? '_Dark'
        : '_Light';
    final imageUrls = List.generate(
      6,
      (i) =>
          '${AppConfig.assetsBaseURL}/Carousel_${i + 1}_${isMobile ? 'ratio4x5' : 'ratio2x1'}_V5${i == 0 ? slide1Suffix : ''}.png',
    );

    return Semantics(
      label: L10n.of(context).pageLabel(L10n.of(context).welcome),
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (isMobile)
              Image.asset(
                theme.brightness == Brightness.dark
                    ? 'assets/pangea/world_map_background_dark.png'
                    : 'assets/pangea/world_map_background.png',
                fit: BoxFit.cover,
                excludeFromSemantics: true,
              )
            else ...[
              ColoredBox(color: theme.colorScheme.surface),
              Image.asset(
                'assets/pangea/star_background.png',
                fit: BoxFit.cover,
                excludeFromSemantics: true,
              ),
            ],
            SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 32.0),
                  // The carousel is the flexible element: it absorbs whatever
                  // height is left after the buttons, which are laid out at
                  // their natural size so they can never be pushed off screen.
                  Expanded(
                    child: _LoginCarousel(
                      isMobile: isMobile,
                      imageUrls: imageUrls,
                      labels: _labels,
                      onPageChange: (index) {
                        if (mounted) {
                          setState(() => _currentIndex = index);
                        }
                      },
                      controller: _carouselController,
                    ),
                  ),
                  const SizedBox(height: 24.0),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      imageUrls.length,
                      (index) => AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        height: 8,
                        width: 8,
                        decoration: BoxDecoration(
                          color: _currentIndex == index
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outlineVariant,
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24.0),
                  Center(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 300),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          spacing: 8.0,
                          children: [
                            ElevatedButton(
                              onPressed: () => context.go('/home/signup'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    theme.colorScheme.primaryContainer,
                                foregroundColor:
                                    theme.colorScheme.onPrimaryContainer,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    L10n.of(context).getStarted,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                foregroundColor: theme.colorScheme.onSurface,
                                backgroundColor: theme.colorScheme.surface
                                    .withValues(alpha: 0.4),
                              ),
                              onPressed: () => context.go('/home/login'),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    L10n.of(context).loginToAccount,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoginCarousel extends StatelessWidget {
  /// Reserved space above the narrow slide image for a two-line headline:
  /// one line at size 24 measures 29, so two plus breathing room comes to 64.
  /// The strip grows past this when scaled text needs it, rather than clipping.
  static const double _headlineStripHeight = 64.0;

  /// Wide slides cap at the width where FluffyThemes switches to column mode,
  /// so this screen changes character at the same width as the rest of the app.
  static const double _wideSlideMaxWidth =
      FluffyThemes.columnWidth * 2 + FluffyThemes.navRailWidth;

  final bool isMobile;
  final List<String> imageUrls;
  final List<String?> labels;
  final Function(int) onPageChange;
  final CarouselSliderController controller;

  const _LoginCarousel({
    required this.isMobile,
    required this.imageUrls,
    required this.labels,
    required this.onPageChange,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.widthOf(context);

    if (isMobile) {
      // Natural height is the full-width 4:5 slide plus the headline strip.
      // When the window is shorter than that, the cap lets the carousel
      // shrink and the slide image scales down instead of hiding the buttons.
      return Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: screenWidth * 1.25 + _headlineStripHeight,
          ),
          child: SizedBox(
            width: screenWidth,
            child: CarouselSlider(
              items: imageUrls
                  .mapIndexed(
                    (index, imageUrl) => Column(
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(
                            minHeight: _headlineStripHeight,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                            child: labels[index] == null
                                ? const SizedBox.shrink()
                                : _SlideHeadline(labels[index]!),
                          ),
                        ),
                        Expanded(
                          child: CachedNetworkImage(
                            imageUrl: imageUrl,
                            width: double.infinity,
                            fit: BoxFit.contain,
                            errorWidget: (context, url, error) =>
                                Center(child: PangeaLogoSvg(width: 128.0)),
                          ),
                        ),
                      ],
                    ),
                  )
                  .toList(),
              carouselController: controller,
              options: CarouselOptions(
                height: double.infinity,
                viewportFraction: 1.0,
                autoPlay: true,
                autoPlayInterval: const Duration(seconds: 8),
                onPageChanged: (index, _) => onPageChange(index),
              ),
            ),
          ),
        ),
      );
    }

    // Desktop
    return CarouselSlider(
      items: imageUrls
          .mapIndexed(
            (index, imageUrl) => ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _wideSlideMaxWidth),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: CachedNetworkImage(
                      imageUrl: imageUrl,
                      width: double.infinity,
                      fit: BoxFit.contain,
                      errorWidget: (context, url, error) =>
                          Center(child: PangeaLogoSvg(width: 256.0)),
                    ),
                  ),
                  const SizedBox(height: 24.0),
                  // Reserve roughly one headline line so slide 1, which has
                  // no headline, keeps its image aligned with the others.
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 30.0),
                    child: labels[index] == null
                        ? const SizedBox.shrink()
                        : _SlideHeadline(labels[index]!),
                  ),
                ],
              ),
            ),
          )
          .toList(),
      carouselController: controller,
      options: CarouselOptions(
        viewportFraction: 1.0,
        autoPlay: true,
        autoPlayInterval: const Duration(seconds: 8),
        onPageChanged: (index, _) {
          onPageChange(index);
        },
      ),
    );
  }
}

/// A slide headline punched out of the backdrop: a fill in the darkest brand
/// tone over a stroke in the surface colour, so it stays legible over the map
/// in light mode and dark mode alike.
class _SlideHeadline extends StatelessWidget {
  final String text;

  const _SlideHeadline(this.text);

  static const _style = TextStyle(
    fontSize: 24.0,
    fontWeight: FontWeight.w600,
    height: 29 / 24,
  );

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Stack(
      alignment: Alignment.center,
      children: [
        ExcludeSemantics(
          child: Text(
            text,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: _style.copyWith(
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 3
                ..strokeJoin = StrokeJoin.round
                ..color = colorScheme.surface,
            ),
          ),
        ),
        Text(
          text,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: _style.copyWith(color: colorScheme.onPrimaryContainer),
        ),
      ],
    );
  }
}
