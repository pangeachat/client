import 'dart:async';

import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:fluffychat/widgets/matrix.dart';

class PresenceBuilder extends StatefulWidget {
  final Widget Function(BuildContext context, CachedPresence? presence) builder;
  final String? userId;
  final Client? client;

  const PresenceBuilder({
    required this.builder,
    this.userId,
    this.client,
    super.key,
  });

  @override
  State<PresenceBuilder> createState() => _PresenceBuilderState();
}

class _PresenceBuilderState extends State<PresenceBuilder> {
  CachedPresence? _presence;
  StreamSubscription<CachedPresence>? _sub;

  void _updatePresence(CachedPresence? presence) {
    // #Pangea
    // setState(() {
    //   _presence = presence;
    // });
    if (mounted) setState(() => _presence = presence);
    // Pangea#
  }

  @override
  void initState() {
    super.initState();
    final client = widget.client ?? Matrix.of(context).client;
    final userId = widget.userId;
    if (userId != null) {
      client.fetchCurrentPresence(userId).then(_updatePresence);
      _sub = client.onPresenceChanged.stream
          .where((presence) => presence.userid == userId)
          .listen(_updatePresence);
    }
  }

  // #Pangea
  @override
  void didUpdateWidget(PresenceBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId == widget.userId) return;

    final client = widget.client ?? Matrix.of(context).client;
    final userId = widget.userId;
    if (userId != null) {
      client.fetchCurrentPresence(userId).then(_updatePresence);
      _sub?.cancel();
      _sub = client.onPresenceChanged.stream
          .where((presence) => presence.userid == userId)
          .listen(_updatePresence);
    }
  }
  // Pangea#

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _presence);
}
