import 'package:flutter/foundation.dart';

import 'package:fluffychat/pangea/instructions/instructions_enum.dart';
import 'package:fluffychat/widgets/matrix.dart';

/// The user's settings for whether or not to show instuction messages.
class InstructionSettings {
  final Map<String, bool> instructions;

  /// Tracks the last step index reached for each tutorial, keyed by
  /// [InstructionsEnum.toString()]. Allows mid-tutorial resume.
  final Map<String, int> tutorialStepProgress;

  const InstructionSettings({
    this.instructions = const {},
    this.tutorialStepProgress = const {},
  });

  factory InstructionSettings.fromJson(Map<String, dynamic> json) {
    final Map<String, bool> instructions = {};
    for (final key in InstructionsEnum.values) {
      instructions[key.toString()] = json[key.toString()] ?? false;
    }
    final Map<String, int> tutorialStepProgress = {};
    final progressData = json['tutorialStepProgress'];
    if (progressData is Map) {
      for (final entry in progressData.entries) {
        if (entry.value is int) {
          tutorialStepProgress[entry.key as String] = entry.value as int;
        }
      }
    }
    return InstructionSettings(
      instructions: instructions,
      tutorialStepProgress: tutorialStepProgress,
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    for (final key in InstructionsEnum.values) {
      data[key.toString()] = instructions[key.toString()];
    }
    data['tutorialStepProgress'] = Map<String, dynamic>.from(
      tutorialStepProgress,
    );
    return data;
  }

  factory InstructionSettings.migrateFromAccountData() {
    final accountData =
        MatrixState.pangeaController.matrixState.client.accountData;
    final Map<String, bool> instructions = {};
    for (final key in InstructionsEnum.values) {
      instructions[key.toString()] =
          (accountData[key.toString()]?.content[key.toString()] as bool?) ??
          false;
    }
    return InstructionSettings(instructions: instructions);
  }

  bool getStatus(InstructionsEnum instruction) {
    return instructions[instruction.toString()] ?? false;
  }

  void setStatus(InstructionsEnum instruction, bool status) {
    instructions[instruction.toString()] = status;
  }

  int getStepProgress(InstructionsEnum instruction) {
    return tutorialStepProgress[instruction.toString()] ?? 0;
  }

  void setStepProgress(InstructionsEnum instruction, int step) {
    tutorialStepProgress[instruction.toString()] = step;
  }

  void clearStepProgress(InstructionsEnum instruction) {
    tutorialStepProgress.remove(instruction.toString());
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! InstructionSettings) return false;

    final entries = instructions.entries.toList()
      ..sort((a, b) => a.key.hashCode.compareTo(b.key.hashCode));

    final otherEntries = other.instructions.entries.toList()
      ..sort((a, b) => a.key.hashCode.compareTo(b.key.hashCode));

    final progressEntries = tutorialStepProgress.entries.toList()
      ..sort((a, b) => a.key.hashCode.compareTo(b.key.hashCode));

    final otherProgressEntries = other.tutorialStepProgress.entries.toList()
      ..sort((a, b) => a.key.hashCode.compareTo(b.key.hashCode));

    return listEquals(
          entries.map((e) => e.key).toList(),
          otherEntries.map((e) => e.key).toList(),
        ) &&
        listEquals(
          entries.map((e) => e.value).toList(),
          otherEntries.map((e) => e.value).toList(),
        ) &&
        listEquals(
          progressEntries.map((e) => e.key).toList(),
          otherProgressEntries.map((e) => e.key).toList(),
        ) &&
        listEquals(
          progressEntries.map((e) => e.value).toList(),
          otherProgressEntries.map((e) => e.value).toList(),
        );
  }

  @override
  int get hashCode {
    final entries = instructions.entries.toList()
      ..sort((a, b) => a.key.hashCode.compareTo(b.key.hashCode));

    final progressEntries = tutorialStepProgress.entries.toList()
      ..sort((a, b) => a.key.hashCode.compareTo(b.key.hashCode));

    return Object.hash(
      Object.hashAll(entries.map((e) => Object.hash(e.key, e.value))),
      Object.hashAll(progressEntries.map((e) => Object.hash(e.key, e.value))),
    );
  }
}
