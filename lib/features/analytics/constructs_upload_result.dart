/// What the server accepted from one upload of construct use batches.
class ConstructsUploadResult {
  final int batchCount;

  /// How many of the batches, counted from the first, the server accepted.
  /// The rest were not sent or not accepted, and must be sent again.
  final int acceptedBatchCount;

  /// The ids the server gave the events it accepted, in the order sent.
  final List<String> acceptedEventIds;

  const ConstructsUploadResult({
    required this.batchCount,
    required this.acceptedBatchCount,
    required this.acceptedEventIds,
  });

  bool get allAccepted => acceptedBatchCount == batchCount;
}
