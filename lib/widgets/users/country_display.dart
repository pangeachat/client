import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';

import 'package:fluffychat/widgets/matrix.dart';

class CountryDisplay extends StatelessWidget {
  final String userId;
  final double maxWidth;

  const CountryDisplay({
    super.key,
    required this.userId,
    this.maxWidth = 200.0,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: FutureBuilder(
        future: MatrixState.pangeaController.userController.getPublicProfile(
          userId,
        ),
        builder: (context, snapshot) {
          final country = snapshot.data?.country;
          if (country == null) {
            return const SizedBox.shrink();
          }

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 4.0,
              children: [
                Icon(Symbols.globe_location_pin, size: 16.0),
                Text(country),
              ],
            ),
          );
        },
      ),
    );
  }
}
