import 'dart:async';

import 'package:flutter/material.dart';

import 'package:audioplayers/audioplayers.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pangea/analytics_misc/analytics_constants.dart';
import 'package:fluffychat/pangea/bot/widgets/bot_face_svg.dart';
import 'package:fluffychat/pangea/constructs/construct_repo.dart';
import 'package:fluffychat/widgets/matrix.dart';

class LevelUpUtil {
  static void showLevelUpDialog(
    int level,
    String? analyticsRoomId,
    String? summaryStateEventId,
    ConstructSummary? constructSummary,
    BuildContext context,
  ) {
    final player = AudioPlayer();
    player.play(
      UrlSource(
        "${AppConfig.assetsBaseURL}/${AnalyticsConstants.levelUpAudioFileName}",
      ),
    );
    final OverlayEntry overlayEntry = OverlayEntry(
      builder: (context) => LevelUpBanner(
        level: level,
      ),
    );

    Overlay.of(context).insert(overlayEntry);

    Future.delayed(const Duration(seconds: 10), () {
      overlayEntry.remove();
      player.dispose();
    });
  }
}

class LevelUpBanner extends StatefulWidget {
  final int level;

  const LevelUpBanner({
    required this.level,
    super.key,
  });

  @override
  _LevelUpBannerState createState() => _LevelUpBannerState();
}

class _LevelUpBannerState extends State<LevelUpBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  bool _showDetails = false; // Track whether the details banner is visible
  String? _constructSummaryText;

  Future<void> _fetchConstructSummary() async {
    try {
      // Pass the required PangeaController instance to the constructor
      // final controller = GetAnalyticsController(pangeaController);
      final constructSummary = await MatrixState.pangeaController.getAnalytics
          .getConstructSummaryFromStateEvent();
      debugPrint(
        "Construct Summary: ${constructSummary?.textSummary}",
      ); // Debug print
      if (constructSummary != null) {
        setState(() {
          _constructSummaryText =
              constructSummary.textSummary; // Use the correct property
        });
      }
    } catch (e) {
      debugPrint("Error fetching construct summary: $e");
    }
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOut,
      ),
    );

    _fetchConstructSummary();

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Darkened overlay
        if (_showDetails)
          GestureDetector(
            onTap: () {
              setState(() {
                _showDetails = false; // Close details when overlay is tapped
              });
            },
            child: Container(
              color: Colors.black.withOpacity(0.5), // Semi-transparent overlay
            ),
          ),
        SlideTransition(
          position: _slideAnimation,
          child: Align(
            alignment: Alignment.topCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Main banner
                Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.5,
                  ),
                  margin: const EdgeInsets.only(top: 16),
                  decoration: BoxDecoration(
                    color: widget.level > 10
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(
                    vertical: 16,
                    horizontal: 24,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          RichText(
                            text: TextSpan(
                              children: [
                                const TextSpan(
                                  text: "Congratulations on reaching ",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const TextSpan(
                                  text: "Level ",
                                  style: TextStyle(
                                    color: Colors.yellow,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                TextSpan(
                                  text: "${widget.level}",
                                  style: const TextStyle(
                                    color: Colors.yellow,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Image.asset(
                            'assets/Star.png', // Path to the star image
                            height: 24, // Adjust height to match text size
                            width: 24, // Adjust width to match text size
                          ),
                        ],
                      ),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _showDetails = !_showDetails; // Toggle details
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                        ),
                        child: const Row(
                          children: [
                            Text("See details"),
                            Icon(Icons.arrow_downward),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  child: _showDetails
                      ? Container(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.5,
                          ),
                          margin: const EdgeInsets.only(
                            top: 16,
                          ), // Add margin at the top
                          decoration: BoxDecoration(
                            color:
                                Colors.black, // Set background color to black
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Stats Table
                              Table(
                                columnWidths: const {
                                  0: IntrinsicColumnWidth(), // Emoji column
                                  1: FlexColumnWidth(), // Text column
                                  2: IntrinsicColumnWidth(), // XP column
                                },
                                defaultVerticalAlignment:
                                    TableCellVerticalAlignment.middle,
                                children: const [
                                  TableRow(
                                    children: [
                                      Text(
                                        "📖", // Book emoji for Vocabulary
                                        style: TextStyle(fontSize: 18),
                                        textAlign: TextAlign.center,
                                      ),
                                      Text(
                                        "Vocabulary Practice",
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      Text(
                                        "+150 XP",
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                  TableRow(
                                    children: [
                                      Text(
                                        "🧩", // Puzzle piece emoji for Grammar
                                        style: TextStyle(fontSize: 18),
                                        textAlign: TextAlign.center,
                                      ),
                                      Text(
                                        "Grammar Practice",
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      Text(
                                        "+50 XP",
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                  TableRow(
                                    children: [
                                      Text(
                                        "📝", // Paper with pencil emoji for Writing Practice
                                        style: TextStyle(fontSize: 18),
                                        textAlign: TextAlign.center,
                                      ),
                                      Text(
                                        "Writing Practice",
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      Text(
                                        "+80 XP",
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                  TableRow(
                                    children: [
                                      Text(
                                        "📄🔊", // Paper with writing and speaker emoji for Listening Practice
                                        style: TextStyle(fontSize: 18),
                                        textAlign: TextAlign.center,
                                      ),
                                      Text(
                                        "Listening Practice",
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      Text(
                                        "+10 XP",
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(
                                height: 24,
                              ), // Add spacing between stats and bot face
                              // Bot Face and Speech Bubble
                              Column(
                                children: [
                                  const BotFace(
                                    width: 100,
                                    expression: BotExpression
                                        .idle, // Use a happy expression
                                  ),
                                  const SizedBox(
                                    height: 8,
                                  ), // Add spacing between bot and bubble
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.2),
                                          blurRadius: 4,
                                          offset: const Offset(2, 2),
                                        ),
                                      ],
                                    ),
                                    child: const Text(
                                      "Congratulations!",
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(
                                height: 24,
                              ), // Add spacing between bot and text box
                              // Text Box
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .secondaryContainer,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  (_constructSummaryText != null
                                      ? Text(
                                          _constructSummaryText!,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                          textAlign: TextAlign.center,
                                        )
                                      : const SizedBox.shrink()) as String,
                                ),
                              ),
                              const SizedBox(
                                height: 24,
                              ), // Add spacing between text box and button
                              // Share with Friends Button
                              ElevatedButton.icon(
                                onPressed: () {
                                  // Add share functionality here
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      Colors.white, // White button background
                                  foregroundColor:
                                      Colors.black, // Black text and icon
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                    horizontal: 24,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                icon: const Icon(Icons.share), // Share icon
                                label: const Text(
                                  "Share with Friends",
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
