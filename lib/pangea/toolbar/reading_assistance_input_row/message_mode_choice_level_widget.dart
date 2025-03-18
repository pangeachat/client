// class MessageModeChoiceLevelWidget extends StatelessWidget {
//   final MessageOverlayController overlayController;
//   final PangeaMessageEvent pangeaMessageEvent;

//   final MorphFeaturesEnum? morphFeature;

//   final PartOfSpeechEnum? partOfSpeech;

//   MessageModeChoiceLevelWidget({
//     super.key,
//     this.morphFeature,
//     this.partOfSpeech,
//     required this.overlayController,
//     required this.pangeaMessageEvent,
//   }) {
//     assert(
//       morphFeature != null ||
//           partOfSpeech != null &&
//               !(morphFeature != null && partOfSpeech != null),
//     );
//   }

//   MorphIcon get icon => MorphIcon(
//         morphFeature: morphFeature?.toShortString() ??
//             MorphFeaturesEnum.Pos.toShortString(),
//         morphTag: partOfSpeech?.toShortString(),
//         showTooltip: true,
//       );

//   String get levelString =>
//       (morphFeature?.toShortString() ?? partOfSpeech?.toShortString())!;

//   bool get isSelected {
//     if (overlayController.modeLevel == null) {
//       return false;
//     }

//     return overlayController.modeLevel?.toLowerCase() ==
//         levelString.toLowerCase();
//   }

//   @override
//   Widget build(BuildContext context) {
//     return IconButton(
//       icon: icon,
//       onPressed: () => overlayController.onChoiceLevelSelection(levelString),
//       isSelected: isSelected,
//       color: isSelected ? Theme.of(context).colorScheme.primary : null,
//       style: ButtonStyle(
//         backgroundColor: WidgetStateProperty.resolveWith<Color?>(
//           (Set<WidgetState> states) {
//             if (states.contains(WidgetState.selected)) {
//               return Theme.of(context).colorScheme.primary.withAlpha(30);
//             }
//             return null;
//           },
//         ),
//       ),
//     );
//   }
// }

// class MessageModeChoice extends StatelessWidget{
//   final MorphFeaturesEnum? morphFeature;

//   final PartOfSpeechEnum? partOfSpeech;

//   bool Function(PangeaToken?) isMatch;

//   final bool isSelected;

//   void Function() onSelect;

//   MessageModeChoice({super.key,
//     this.morphFeature,
//     required this.isSelected,
//     required this.onSelect,
//     this.partOfSpeech,
//   }) {
//     assert(morphFeature != null || partOfSpeech != null);
//   }

//   MorphIcon get icon => MorphIcon(
//         morphFeature: morphFeature?.toShortString() ??
//             MorphFeaturesEnum.Pos.toShortString(),
//         morphTag: partOfSpeech?.toShortString(),
//       );

//    @override
//   Widget build(BuildContext context) {
//     return IconButton(
//         icon: icon,
//         onPressed: onSelect,
//         isSelected: isSelected,
//       );
// }
