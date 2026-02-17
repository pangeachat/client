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
import 'package:fluffychat/pangea/common/config/environment.dart';
import 'package:fluffychat/pangea/common/widgets/pangea_logo_svg.dart';
import 'package:fluffychat/pangea/join_codes/space_code_repo.dart';
import 'package:fluffychat/pangea/login/widgets/app_config_dialog.dart';

class LoginOrSignupView extends StatefulWidget {
  const LoginOrSignupView({super.key});

  @override
  State<LoginOrSignupView> createState() => LoginOrSignupViewState();
}

class LoginOrSignupViewState extends State<LoginOrSignupView> {
  final CarouselSliderController _controller = CarouselSliderController();
  List<String> get _imageFileNames =>
      List.generate(6, (index) => 'Carousel_${index + 1}_ratio2x1.svg');

  List<AppConfigOverride> _overrides = [];
  List<Future> _imageFutures = [];

  @override
  void initState() {
    super.initState();
    _loadOverrides();
    _imageFutures = _imageFileNames.mapIndexed((index, filename) async {
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
    }).toList();
  }

  String? get _cachedSpaceCode => SpaceCodeRepo.spaceCode;

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

  Future<void> _loadOverrides() async {
    final overrides = await Environment.getAppConfigOverrides();
    if (mounted) {
      setState(() => _overrides = overrides);
    }
  }

  Future<void> _setEnvironment() async {
    if (_overrides.isEmpty) return;

    final resp = await showDialog<AppConfigOverride?>(
      context: context,
      builder: (context) => AppConfigDialog(overrides: _overrides),
    );

    await Environment.setAppConfigOverride(resp);
    setState(() {});
  }

  Map<int, Map<String, String>> get _updatedIDs => {
    1: {
      'Edit text': L10n.of(context).appDescription,
      'Edit text header': L10n.of(context).shareYourHobbies,
    },
    2: {'Edit text Header': L10n.of(context).pangeaBot},
    3: {
      'Edit text_2': L10n.of(context).joinWithClassCode,
      'Edit text_4': L10n.of(context).startYourOwn,
    },
    4: {
      'Edit text': L10n.of(context).playConversationGames,
      'Edit text_2': L10n.of(context).guessMyHometown,
    },
    5: {'Edit text_2': L10n.of(context).languageExchange},
    6: {},
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.widthOf(context);
    final isMobile = screenWidth <= 832.0;

    final title = Row(
      spacing: 12.0,
      mainAxisSize: .min,
      children: [
        PangeaLogoSvg(
          width: isMobile ? 32.0 : 56.0,
          forceColor: theme.colorScheme.onSurface,
        ),
        Text(
          AppSettings.applicationName.value,
          style:
              (isMobile
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
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.topCenter,
                child: FutureBuilder(
                  future: Future.wait(_imageFutures),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    } else if (snapshot.hasError) {
                      return SizedBox();
                    }

                    return CarouselSlider(
                      items: snapshot.data!
                          .map(
                            (item) => SvgPicture.string(
                              item,
                              placeholderBuilder: (context) => const Center(
                                child: CircularProgressIndicator(),
                              ),
                            ),
                          )
                          .toList(),
                      carouselController: _controller,
                      options: CarouselOptions(
                        enlargeCenterPage: true,
                        autoPlay: true,
                      ),
                    );
                  },
                ),
              ),
            ),
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
                          backgroundColor: theme.colorScheme.primaryContainer,
                          foregroundColor: theme.colorScheme.onPrimaryContainer,
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
      ),
    );
  }
}
