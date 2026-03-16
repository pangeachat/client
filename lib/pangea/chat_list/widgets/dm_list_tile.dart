import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';

class DMListTile extends StatefulWidget {
  final String title;
  final String subtitle;
  final Future<String> Function() onTap;
  final Widget leading;
  final Widget trailing;
  final EdgeInsets? contentPadding;

  const DMListTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.leading,
    required this.trailing,
    this.contentPadding,
  });

  @override
  State<DMListTile> createState() => DMListTileState();
}

class DMListTileState extends State<DMListTile> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        borderRadius: BorderRadius.circular(AppConfig.borderRadius),
        clipBehavior: Clip.hardEdge,
        child: ListTile(
          contentPadding: widget.contentPadding,
          leading: widget.leading,
          trailing: widget.trailing,
          title: Text(widget.title),
          subtitle: Text(widget.subtitle),
          onTap: _loading
              ? null
              : () async {
                  setState(() => _loading = true);
                  try {
                    final resp = await showFutureLoadingDialog<String>(
                      context: context,
                      future: widget.onTap,
                    );
                    if (!mounted) return;
                    if (resp.isError) return;
                    context.go('/rooms/${resp.result}');
                  } finally {
                    if (mounted) setState(() => _loading = false);
                  }
                },
        ),
      ),
    );
  }
}
