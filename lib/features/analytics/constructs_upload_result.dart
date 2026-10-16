/// What the server accepted from one upload of construct use batches.
class ConstructsUploadResult {
  final int batchCount;

  /// How many of the batches, counted from the first, the server accepted.
  /// The rest were not sent or not accepted, and must be sent again.
  final int acceptedBatchCount;

  /// How many leading uses of the batch at [acceptedBatchCount] the server
  /// accepted. Non-zero only for a batch split across events; those uses must
  /// not be sent again.
  final int partlyAcceptedUseCount;

  /// The ids the server gave the events it accepted, in the order sent.
  final List<String> acceptedEventIds;

  const ConstructsUploadResult({
    required this.batchCount,
    required this.acceptedBatchCount,
    required this.partlyAcceptedUseCount,
    required this.acceptedEventIds,
  });

  bool get allAccepted => acceptedBatchCount == batchCount;
}
