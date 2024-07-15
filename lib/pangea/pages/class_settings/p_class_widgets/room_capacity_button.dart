import 'package:adaptive_dialog/adaptive_dialog.dart';
import 'package:fluffychat/pages/chat_details/chat_details.dart';
import 'package:fluffychat/pangea/extensions/pangea_room_extension/pangea_room_extension.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/l10n.dart';
import 'package:future_loading_dialog/future_loading_dialog.dart';
import 'package:matrix/matrix.dart';

class RoomCapacityListTile extends StatefulWidget {
  final Room? room;
  final ChatDetailsController? controller;
  const RoomCapacityListTile({
    super.key,
    this.room,
    this.controller,
  });

  @override
  RoomCapacityListTileState createState() => RoomCapacityListTileState();
}

class RoomCapacityListTileState extends State<RoomCapacityListTile> {
  int? capacity;
  String? nonAdmins;

  RoomCapacityListTileState({Key? key});

  @override
  void initState() {
    super.initState();
    capacity = widget.room?.capacity;
    widget.room?.numNonAdmins.then(
      (value) => setState(() {
        nonAdmins = value.toString();
        overCapacity();
      }),
    );
  }

  @override
  void didUpdateWidget(RoomCapacityListTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room != widget.room) {
      capacity = widget.room?.capacity;
      widget.room?.numNonAdmins.then(
        (value) => setState(() {
          nonAdmins = value.toString();
          overCapacity();
        }),
      );
    }
  }

  Future<void> overCapacity() async {
    if ((widget.room?.isRoomAdmin ?? false) &&
        capacity != null &&
        nonAdmins != null &&
        int.parse(nonAdmins!) > capacity!) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            L10n.of(context)!.roomExceedsCapacity,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final iconColor = Theme.of(context).textTheme.bodyLarge!.color;
    return Column(
      children: [
        ListTile(
          onTap: (widget.room?.isRoomAdmin ?? true) ? setRoomCapacity : null,
          leading: CircleAvatar(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            foregroundColor: iconColor,
            child: const Icon(Icons.reduce_capacity),
          ),
          subtitle: capacity != null
              ? Text(
                  (nonAdmins != null) ? '$nonAdmins/$capacity' : '$capacity',
                )
              : null,
          title: Text(
            L10n.of(context)!.roomCapacity,
            style: TextStyle(
              color: Theme.of(context).colorScheme.secondary,
              fontWeight: FontWeight.bold,
            ),
          ),
          trailing: const Icon(Icons.edit),
        ),
      ],
    );
  }

  Future<void> setCapacity(int newCapacity) async {
    capacity = newCapacity;
  }

  Future<void> setRoomCapacity() async {
    final input = await showTextInputDialog(
      context: context,
      title: L10n.of(context)!.roomCapacity,
      message: L10n.of(context)!.roomCapacityExplanation,
      okLabel: L10n.of(context)!.ok,
      cancelLabel: L10n.of(context)!.cancel,
      textFields: [
        DialogTextField(
          initialText: ((capacity != null) ? '$capacity' : ''),
          keyboardType: TextInputType.number,
          maxLength: 3,
          validator: (value) {
            if (value == null ||
                value.isEmpty ||
                int.tryParse(value) == null ||
                int.parse(value) < 0) {
              return L10n.of(context)!.enterNumber;
            }
            if (nonAdmins != null && int.parse(value) < int.parse(nonAdmins!)) {
              return L10n.of(context)!.capacitySetTooLow;
            }
            return null;
          },
        ),
      ],
    );
    if (input == null ||
        input.first == "" ||
        int.tryParse(input.first) == null) {
      return;
    }

    final newCapacity = int.parse(input.first);
    final success = await showFutureLoadingDialog(
      context: context,
      future: () => ((widget.room != null)
          ? (widget.room!.updateRoomCapacity(
              capacity = newCapacity,
            ))
          : setCapacity(newCapacity)),
    );
    if (success.error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            L10n.of(context)!.roomCapacityHasBeenChanged,
          ),
        ),
      );
      setState(() {});
    }
  }
}
