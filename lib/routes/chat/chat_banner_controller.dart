import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/common/utils/error_handler.dart';
import 'package:fluffychat/widgets/matrix.dart';

typedef BannerExecutor = void Function(Completer<void> completer);

class BannerQueueEntry {
  final BannerExecutor show;
  final String overlayKey;
  final Duration timeout;

  BannerQueueEntry({
    required this.show,
    required this.overlayKey,
    this.timeout = const Duration(seconds: 10),
  });
}

class ChatBannerController {
  ChatBannerController();

  Completer<void>? _currentBannerCompleter;
  final Queue<BannerQueueEntry> _bannerQueue = Queue();

  int get queueLength => _bannerQueue.length;

  void dispose() {
    // Complete the current banner completer to allow any showing banner to close
    if (_currentBannerCompleter != null &&
        !_currentBannerCompleter!.isCompleted) {
      _currentBannerCompleter!.complete();
    }

    _currentBannerCompleter = null;
    _bannerQueue.clear(); // Clear any pending banners in the queue
  }

  // The banner widget created by showBanner should call complete on the provided
  // Completer when it is dismissed or if it fails to show to allow the next banner to show
  void addBanner(
    BannerExecutor showBanner, {
    required String overlayKey,
    Duration timeout = const Duration(seconds: 30),
  }) {
    if (_bannerQueue.any((b) => b.overlayKey == overlayKey)) return;

    _bannerQueue.add(
      BannerQueueEntry(
        show: showBanner,
        overlayKey: overlayKey,
        timeout: timeout,
      ),
    );

    if (_currentBannerCompleter == null) {
      showNextBanner();
    }
  }

  Future<void> showNextBanner() async {
    if (_currentBannerCompleter != null || _bannerQueue.isEmpty) {
      return; // A banner is currently showing or no banners to show
    }

    final completer = Completer<void>();
    _currentBannerCompleter = completer;
    final bannerQueueEntry = _bannerQueue.removeFirst();
    final show = bannerQueueEntry.show;
    final timeout = bannerQueueEntry.timeout;
    final overlayKey = bannerQueueEntry.overlayKey;

    try {
      show(completer);

      await completer.future.timeout(
        timeout,
        onTimeout: () {
          debugPrint(
            "Banner '$overlayKey' timed out after ${timeout.inSeconds}s",
          );
          MatrixState.pAnyState.closeOverlay(overlayKey);
          if (!completer.isCompleted) completer.complete();
        },
      );
    } catch (e, s) {
      ErrorHandler.logError(e: e, s: s, data: {"overlayKey": overlayKey});
    } finally {
      _currentBannerCompleter = null;
      showNextBanner(); // Show the next banner in the queue
    }
  }
}
