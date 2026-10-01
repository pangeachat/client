/// Why a Mission is locked: the learner has [earned] of the [required] stars
/// across the Missions before it. Each earlier Mission counts only up to its
/// own threshold, so surplus stars in one Mission never unlock a later one
/// (#9333 prototype).
class MissionLock {
  final int earned;
  final int required;

  const MissionLock({required this.earned, required this.required});
}
