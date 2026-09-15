import 'package:flutter/material.dart';

/// Off web there is no DOM, so nothing can take the pointer away from Flutter
/// and there is nothing to shield. See `embed_pointer_shield.dart`.
class EmbedPointerShield extends StatelessWidget {
  const EmbedPointerShield({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
