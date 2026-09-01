import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:fluffychat/features/overlay/overlay.dart';
import 'package:fluffychat/features/overlay/overlay_display_details.dart';
import 'package:fluffychat/routes/chat/choreographer/igc/autocorrect_popup.dart';
import 'package:fluffychat/widgets/matrix.dart';

class AutocorrectSpan extends WidgetSpan {
  AutocorrectSpan({
    required String transformTargetId,
    required String currentText,
    required String originalText,
    required VoidCallback onUndo,
    required TextStyle style,
  }) : super(
         alignment: PlaceholderAlignment.middle,
         child: CompositedTransformTarget(
           link: MatrixState.pAnyState.layerLinkAndKey(transformTargetId).link,
           child: Builder(
             builder: (context) {
               // A WidgetSpan child is already scaled by the placeholder it
               // sits in; scaling its text here too squares the device text
               // size, so corrected text grows past the rest of the input
               // (#8704).
               return RichText(
                 key: MatrixState.pAnyState
                     .layerLinkAndKey(transformTargetId)
                     .key,
                 text: TextSpan(
                   text: currentText,
                   style: style,
                   recognizer: TapGestureRecognizer()
                     ..onTap = () {
                       OverlayUtil.showOverlay(
                         context: context,
                         child: AutocorrectPopup(
                           originalText: originalText,
                           onUndo: onUndo,
                         ),
                         displayDetails: TransformOverlayDisplayDetails(
                           overlayKey: "autocorrect_span_$transformTargetId",
                           transformTargetId: transformTargetId,
                         ),
                       );
                     },
                 ),
               );
             },
           ),
         ),
       );
}
