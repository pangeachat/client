import 'package:flutter/material.dart';

/// The heading row of a Learning settings section, shared so every section's
/// title sits on the same padding.
class SettingsSectionHeader extends StatelessWidget {
  final String title;

  const SettingsSectionHeader({super.key, required this.title});

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(
      title,
      style: TextStyle(
        color: Theme.of(context).colorScheme.secondary,
        fontWeight: FontWeight.bold,
      ),
    ),
  );
}
