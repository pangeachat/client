import 'package:flutter/material.dart';

enum OverlayPosition {
  above,
  below;

  Alignment get targetAnchor => switch (this) {
    OverlayPosition.above => Alignment.topCenter,
    OverlayPosition.below => Alignment.bottomCenter,
  };

  Alignment get followerAnchor => switch (this) {
    OverlayPosition.above => Alignment.bottomCenter,
    OverlayPosition.below => Alignment.topCenter,
  };
}
