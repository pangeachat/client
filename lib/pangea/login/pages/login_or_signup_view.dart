import 'package:flutter/material.dart';

import 'package:carousel_slider/carousel_slider.dart';
import 'package:collection/collection.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/pangea_logo_svg.dart';
import 'package:fluffychat/pangea/join_codes/space_code_repo.dart';
import 'package:fluffychat/utils/platform_infos.dart';

class LoginOrSignupView extends StatefulWidget {
  const LoginOrSignupView({super.key});

  @override
  State<LoginOrSignupView> createState() => _LoginOrSignupViewState();
}

class _LoginOrSignupViewState extends State<LoginOrSignupView> {
  static const _breakpoint = 832.0;

  final CarouselSliderController _carouselController =
      CarouselSliderController();

  bool _isMobile = PlatformInfos.isMobile;
  int _currentIndex = 0;

  Future<List<String>>? _svgFuture;
  final Map<String, String> _rawSvgCache = {};
  final Map<String, String> _processedSvgCache = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final width = MediaQuery.sizeOf(context).width;
      _isMobile = width <= _breakpoint;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width <= _breakpoint;

    final breakpointChanged = _isMobile != isMobile;

    if (_svgFuture == null || breakpointChanged) {
      _isMobile = isMobile;
      _svgFuture = _loadAllSvgs();
    }
  }

  String? get _cachedSpaceCode => SpaceCodeRepo.spaceCode;

  List<String> get _imageFileNames {
    final ratio = _isMobile ? 'ratio4x5' : 'ratio2x1';
    return List.generate(6, (i) => 'Carousel_${i + 1}_$ratio.svg');
  }

  Future<List<String>> _loadAllSvgs() async {
    final files = _imageFileNames;

    return Future.wait(
      files.mapIndexed((index, filename) async {
        // 1️⃣ RAW CACHE
        if (!_rawSvgCache.containsKey(filename)) {
          final resp = await http.get(
            Uri.parse('${AppConfig.assetsBaseURL}/$filename'),
          );

          if (resp.statusCode != 200) {
            throw Exception('Failed to load $filename');
          }

          _rawSvgCache[filename] = resp.body;
        }

        final rawSvg = _rawSvgCache[filename]!;

        // 2️⃣ PROCESSED CACHE KEY
        final processedKey = filename;

        if (_processedSvgCache.containsKey(processedKey)) {
          return _processedSvgCache[processedKey]!;
        }

        final replacements = _updatedIDs[index + 1];

        final processed = replacements == null
            ? rawSvg
            : _updateSvgText(rawSvg: rawSvg, replacements: replacements);

        _processedSvgCache[processedKey] = processed;

        return processed;
      }),
    );
  }

  String _updateSvgText({
    required String rawSvg,
    required Map<String, String> replacements,
  }) {
    final document = XmlDocument.parse(rawSvg);

    for (final entry in replacements.entries) {
      final parent = document
          .findAllElements('*')
          .firstWhereOrNull((e) => e.getAttribute('id') == entry.key);

      if (parent == null) continue;

      final tspan = parent.findAllElements('tspan').firstOrNull;
      if (tspan == null) continue;

      tspan.children
        ..clear()
        ..add(XmlText(entry.value));
    }

    return document.toXmlString();
  }

  Map<int, Map<String, String>> get _updatedIDs => {
    1: {
      'Edit text': L10n.of(context).learnLanguageWhileTexting,
      'Edit text header': L10n.of(context).shareYourHobbies,
    },
    2: {
      'Edit text Header': L10n.of(context).pangeaBot,
      'Edit text': L10n.of(context).writeAndSpeakWorryFree,
    },
    3: {
      'Edit text': L10n.of(context).joinLearningCommunities,
      'Edit text_2': L10n.of(context).joinWithClassCode,
      'Edit text_4': L10n.of(context).startYourOwn,
    },
    4: {
      'Edit text': L10n.of(context).playConversationGames,
      'Edit text_2': L10n.of(context).guessMyHometown,
    },
    5: {
      'Edit text': L10n.of(context).jumpIntoConversation,
      'Edit text_2': L10n.of(context).languageExchange,
    },
    6: {'Edit text': L10n.of(context).playPersonalizedGames},
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<List<String>>(
          future: _svgFuture,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final svgs = snapshot.data!;

            return LayoutBuilder(
              builder: (context, constraints) {
                final isMobile = constraints.maxWidth <= _breakpoint;

                return Column(
                  children: [
                    _LoginCarousel(
                      isMobile: isMobile,
                      svgs: svgs,
                      onPageChange: (index) {
                        if (mounted) {
                          setState(() => _currentIndex = index);
                        }
                      },
                      controller: _carouselController,
                    ),
                    if (isMobile) ...[
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          svgs.length,
                          (index) => AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            height: 8,
                            width: _currentIndex == index ? 24 : 8,
                            decoration: BoxDecoration(
                              color: _currentIndex == index
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.outlineVariant,
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                    Expanded(
                      flex: 1,
                      child: Center(
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 480),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    PangeaLogoSvg(
                                      width: isMobile ? 32 : 48,
                                      forceColor: theme.colorScheme.onSurface,
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      AppSettings.applicationName.value,
                                      style:
                                          (isMobile
                                                  ? theme
                                                        .textTheme
                                                        .headlineSmall
                                                  : theme
                                                        .textTheme
                                                        .displaySmall)
                                              ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                              ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 24),
                                ElevatedButton(
                                  // push instead of go so the app bar back button doesn't go to the language selection page
                                  // https://github.com/pangeachat/client/issues/4421
                                  onPressed: () => context.push(
                                    _cachedSpaceCode != null
                                        ? '/home/language/signup'
                                        : '/home/language',
                                  ),
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
                                const SizedBox(height: 12),
                                TextButton(
                                  style: TextButton.styleFrom(
                                    foregroundColor:
                                        theme.colorScheme.onPrimaryContainer,
                                  ),
                                  onPressed: () => context.go('/home/login'),
                                  child: Text(
                                    L10n.of(context).loginToAccount,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _LoginCarousel extends StatelessWidget {
  final bool isMobile;
  final List<String> svgs;
  final Function(int) onPageChange;
  final CarouselSliderController controller;

  const _LoginCarousel({
    required this.isMobile,
    required this.svgs,
    required this.onPageChange,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (isMobile) {
      final screenWidth = MediaQuery.widthOf(context);
      return SizedBox(
        width: screenWidth,
        height: screenWidth * 1.25,
        child: CarouselSlider(
          items: svgs.map((svg) => SvgPicture.string(svg)).toList(),
          carouselController: controller,
          options: CarouselOptions(
            height: double.infinity,
            viewportFraction: 1,
            autoPlay: true,
            onPageChanged: (index, _) => onPageChange(index),
          ),
        ),
      );
    }

    // Desktop
    return Expanded(
      flex: 2,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Padding(
            padding: EdgeInsetsGeometry.symmetric(horizontal: 100.0),
            child: CarouselSlider(
              items: svgs
                  .map(
                    (svg) => Padding(
                      padding: EdgeInsetsGeometry.symmetric(horizontal: 2.0),
                      child: SizedBox.expand(child: SvgPicture.string(svg)),
                    ),
                  )
                  .toList(),
              carouselController: controller,
              options: CarouselOptions(
                viewportFraction: 0.8,
                autoPlay: true,
                onPageChanged: (index, _) {
                  onPageChange(index);
                },
              ),
            ),
          ),
          Positioned(
            left: 20,
            child: IconButton(
              icon: Icon(Icons.chevron_left),
              onPressed: controller.previousPage,
              style: IconButton.styleFrom(
                backgroundColor: theme.colorScheme.surface,
                foregroundColor: theme.colorScheme.onSurface,
              ),
            ),
          ),
          Positioned(
            right: 20,
            child: IconButton(
              icon: Icon(Icons.chevron_right),
              onPressed: controller.nextPage,
              style: IconButton.styleFrom(
                backgroundColor: theme.colorScheme.surface,
                foregroundColor: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
