import 'package:flutter/material.dart';

import 'package:flutter_gen/gen_l10n/l10n.dart';

import 'package:fluffychat/pangea/find_your_people/find_your_people.dart';

class FindYourPeopleView extends StatelessWidget {
  final FindYourPeopleState controller;

  const FindYourPeopleView({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.of(context).findYourPeople),
      ),
      body: const Center(),
    );
  }
}
