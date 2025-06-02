import 'package:flutter/material.dart';

import 'package:fluffychat/pangea/find_your_people/find_your_people_view.dart';

class FindYourPeople extends StatefulWidget {
  const FindYourPeople({super.key});

  @override
  State<FindYourPeople> createState() => FindYourPeopleState();
}

class FindYourPeopleState extends State<FindYourPeople> {
  @override
  Widget build(BuildContext context) {
    return FindYourPeopleView(controller: this);
  }
}
