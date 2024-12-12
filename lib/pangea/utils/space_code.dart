import 'dart:convert';

import 'package:adaptive_dialog/adaptive_dialog.dart';
import 'package:fluffychat/pangea/controllers/pangea_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/l10n.dart';
import 'package:matrix/matrix.dart';

class SpaceCodeUtil {
  static const codeLength = 7;

  static bool isValidCode(String? spacecode) {
    if (spacecode == null) return false;
    return spacecode.length == codeLength && spacecode.contains(r'[0-9]');
  }

  static Future<String> generateSpaceCode(Client client) async {
    final response = await client.httpClient.get(
      Uri.parse(
        '${client.homeserver}/_synapse/client/pangea/v1/request_room_code',
      ),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${client.accessToken}',
      },
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to generate room code: $response');
    }
    final roomCodeResult = jsonDecode(response.body);
    if (roomCodeResult['access_code'] is String) {
      return roomCodeResult['access_code'] as String;
    } else {
      throw Exception('Invalid response, access_code not found $response');
    }
  }

  static Future<void> joinWithSpaceCodeDialog(
    BuildContext context,
    PangeaController pangeaController,
  ) async {
    final List<String>? spaceCode = await showTextInputDialog(
      context: context,
      title: L10n.of(context).joinWithClassCode,
      okLabel: L10n.of(context).ok,
      cancelLabel: L10n.of(context).cancel,
      textFields: [
        DialogTextField(hintText: L10n.of(context).joinWithClassCodeHint),
      ],
    );
    if (spaceCode == null || spaceCode.single.isEmpty) return;
    await pangeaController.classController.joinClasswithCode(
      context,
      spaceCode.first,
    );
  }

  static messageDialog(
    BuildContext context,
    String title,
    void Function()? action,
  ) =>
      showDialog(
        context: context,
        useRootNavigator: false,
        builder: (context) => AlertDialog(
          content: Text(title),
          actions: [
            TextButton(
              onPressed: action,
              child: Text(L10n.of(context).ok),
            ),
          ],
        ),
      );
}
