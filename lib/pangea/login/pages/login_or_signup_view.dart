import 'package:flutter/material.dart';

import 'package:carousel_slider/carousel_slider.dart';
import 'package:collection/collection.dart';
import 'package:flutter_svg/svg.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pangea/common/widgets/pangea_logo_svg.dart';
import 'package:fluffychat/pangea/join_codes/space_code_repo.dart';

class LoginOrSignupView extends StatefulWidget {
  const LoginOrSignupView({super.key});

  @override
  State<LoginOrSignupView> createState() => LoginOrSignupViewState();
}

class LoginOrSignupViewState extends State<LoginOrSignupView> {
  bool _isMobile = false;
  final CarouselSliderController _controller = CarouselSliderController();

  List<String> get _imageFileNames {
    final ratioString = _isMobile ? 'ratio4x5' : 'ratio2x1';
    return List.generate(
      6,
      (index) => 'Carousel_${index + 1}_$ratioString.svg',
    );
  }

  // List<AppConfigOverride> _overrides = [];
  List<Future> _imageFutures = [];

  @override
  void initState() {
    super.initState();
    // _loadOverrides();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _isMobile = MediaQuery.widthOf(context) <= 832.0;
      _updateImageFutures();
    });
  }

  String? get _cachedSpaceCode => SpaceCodeRepo.spaceCode;

  void _updateImageFutures() {
    if (mounted) {
      setState(() {
        _imageFutures = _imageFileNames.mapIndexed(_loadSVG).toList();
      });
    }
  }

  String updateSvgText({
    required String rawSvg,
    required Map<String, String> replacements,
  }) {
    debugPrint("Loading and updating SVG with replacements: $replacements");
    final document = XmlDocument.parse(rawSvg);

    for (final entry in replacements.entries) {
      try {
        final parentId = entry.key;
        final newText = entry.value;
        final parentElement = document
            .findAllElements('*')
            .firstWhereOrNull(
              (element) => element.getAttribute('id') == parentId,
            );

        if (parentElement == null) {
          throw Exception(
            'Parent element with id $parentId not found. SVG: ${document.toString()}',
          );
        }
        final textElement = parentElement.findAllElements('tspan').first;
        textElement.children.clear();
        textElement.children.add(XmlText(newText));
      } catch (e) {
        debugPrint(
          'Error updating SVG for id ${entry.key}: $e. SVG: ${document.toString()}',
        );
      }
    }

    return document.toXmlString();
  }

  Future<String> _loadSVG(int index, String filename) async {
    final resp = await http.get(
      Uri.parse('${AppConfig.assetsBaseURL}/$filename'),
    );
    if (resp.statusCode != 200) {
      throw Exception('Failed to load image: $filename');
    }

    final svg = resp.body;
    final entry = _updatedIDs[index + 1];
    if (entry != null) {
      return updateSvgText(rawSvg: svg, replacements: entry);
    }
    return resp.body;
  }

  // Future<void> _loadOverrides() async {
  //   final overrides = await Environment.getAppConfigOverrides();
  //   if (mounted) {
  //     setState(() => _overrides = overrides);
  //   }
  // }

  // Future<void> _setEnvironment() async {
  //   if (_overrides.isEmpty) return;

  //   final resp = await showDialog<AppConfigOverride?>(
  //     context: context,
  //     builder: (context) => AppConfigDialog(overrides: _overrides),
  //   );

  //   await Environment.setAppConfigOverride(resp);
  //   setState(() {});
  // }

  Map<int, Map<String, String>> get _updatedIDs => {
    1: {
      'Edit text': L10n.of(context).appDescription,
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
    final title = Row(
      spacing: 12.0,
      mainAxisSize: .min,
      children: [
        PangeaLogoSvg(
          width: _isMobile ? 32.0 : 56.0,
          forceColor: theme.colorScheme.onSurface,
        ),
        Text(
          AppSettings.applicationName.value,
          style:
              (_isMobile
                      ? theme.textTheme.headlineSmall
                      : theme.textTheme.displayMedium)
                  ?.copyWith(fontWeight: FontWeight.bold),
        ),
      ],
    );

    return Scaffold(
      // appBar: Environment.isStagingEnvironment && _overrides.isNotEmpty
      //     ? AppBar(
      //         actions: [
      //           IconButton(
      //             icon: const Icon(Icons.settings_outlined),
      //             onPressed: _setEnvironment,
      //           ),
      //         ],
      //       )
      //     : null,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth <= 832.0;

          // Only regenerate if breakpoint changes
          if (_isMobile != isMobile) {
            _isMobile = isMobile;
            _updateImageFutures();
          }

          return SafeArea(
            child: Column(
              children: [
                FutureBuilder(
                  future: Future.wait(_imageFutures),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    } else if (snapshot.hasError) {
                      return SizedBox();
                    }

                    return AspectRatio(
                      aspectRatio: _isMobile ? 4 / 5 : 2 / 1,
                      child: CarouselSlider(
                        items: snapshot.data!
                            .map(
                              (item) => SizedBox.expand(
                                child: SvgPicture.string(
                                  item,
                                  fit: BoxFit.contain, // 🔥 important change
                                  alignment: Alignment.topCenter,
                                ),
                              ),
                            )
                            .toList(),
                        carouselController: _controller,
                        options: CarouselOptions(
                          height: double.infinity,
                          viewportFraction: _isMobile ? 1.0 : 0.8,
                          enlargeCenterPage: !_isMobile,
                          autoPlay: true,
                        ),
                      ),
                    );
                  },
                ),
                // Expanded(
                //   flex: 2,
                // child: FutureBuilder(
                //   future: Future.wait(_imageFutures),
                //   builder: (context, snapshot) {
                //     if (snapshot.connectionState == ConnectionState.waiting) {
                //       return const Center(child: CircularProgressIndicator());
                //     } else if (snapshot.hasError) {
                //       return SizedBox();
                //     }

                //     return CarouselSlider(
                //         items: snapshot.data!
                //             .map(
                //               (item) => SizedBox.expand(
                //                 child: SvgPicture.string(
                //                   item,
                //                   fit: BoxFit.cover, // 🔥 important
                //                   alignment: Alignment.center,
                //                 ),
                //               ),
                //             )
                //             .toList(),
                //         carouselController: _controller,
                //         options: CarouselOptions(
                //           height: double.infinity,
                //           enlargeCenterPage: !_isMobile,
                //           autoPlay: true,
                //           viewportFraction: _isMobile ? 1.0 : 0.8,
                //         ),
                //       );
                //     },
                //   ),
                // ),
                Expanded(
                  flex: 1,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 500),
                      child: Column(
                        spacing: isMobile ? 8.0 : 16.0,
                        mainAxisAlignment: .center,
                        children: [
                          title,
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
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton(
                            onPressed: () => context.go('/home/login'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: theme.colorScheme.surface,
                              foregroundColor: theme.colorScheme.onSurface,
                              shadowColor: Colors.transparent,
                              overlayColor: Colors.transparent,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 0,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  L10n.of(context).loginToAccount,
                                  style: TextStyle(fontWeight: FontWeight.bold),
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
          );
        },
      ),
    );
  }
}
