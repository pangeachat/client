import 'package:flutter/foundation.dart';

/// Phones: `flutter drive` forwards the device log to the terminal.
void perfOutput(String line) => debugPrintSynchronously(line);
