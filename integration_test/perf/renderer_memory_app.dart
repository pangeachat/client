// Local, unauthenticated CanvasKit memory regression fixture. Build with:
// fvm flutter build web --profile --no-web-resources-cdn \
//   -t integration_test/perf/renderer_memory_app.dart
// Run with renderer_memory_runner.js. No network services or Sentry init.
import 'dart:js_interop';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:fluffychat/features/bot/widgets/bot_face_svg.dart';

void main() => runApp(const MaterialApp(home: _MemoryFixture()));

@JS('rendererMemoryFrames')
external set _paintedFrames(JSNumber value);

int _frames = 0;

class _MemoryFixture extends StatefulWidget {
  const _MemoryFixture();

  @override
  State<_MemoryFixture> createState() => _MemoryFixtureState();
}

class _MemoryFixtureState extends State<_MemoryFixture>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat();

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mode = Uri.base.queryParameters['mode'] ?? 'painter';
    return Scaffold(
      body: Center(
        child: CustomPaint(
          painter: _AnimatedPaths(_clock),
          size: const Size(300, 300),
          child: mode == 'bot'
              ? const BotFace(width: 300, expression: BotExpression.idle)
              : const SizedBox(width: 300, height: 300),
        ),
      ),
    );
  }
}

class _AnimatedPaths extends CustomPainter {
  _AnimatedPaths(this.clock) : super(repaint: clock);

  final Animation<double> clock;

  @override
  void paint(Canvas canvas, Size size) {
    _paintedFrames = (++_frames).toJS;
    for (var i = 0; i < 80; i++) {
      final phase = clock.value * math.pi * 2 + i;
      final path = Path()
        ..moveTo(0, i * 3.0)
        ..cubicTo(80, 150 + 80 * math.sin(phase), 220, 150, 300, i * 3.0);
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.purple
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(_AnimatedPaths oldDelegate) => false;
}
