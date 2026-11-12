/// What the server answers about a discussion for the learner in one course
/// (synapse `discussion_room`, the preview read).
enum DiscussionAccess {
  /// The course lists it, and Join would place the learner.
  open,

  /// The course does not list it as a discussion (404).
  notListed,

  /// The learner was removed or banned from the course's room for it (403
  /// `PANGEA_DISCUSSION_REMOVED`): they cannot join it again.
  removed,
}

/// The preview of the room Join would place the learner in.
class DiscussionPreview {
  final DiscussionAccess access;

  /// How many students are in that room now, 0 for a new one. Set only
  /// while [access] is [DiscussionAccess.open].
  final int? students;

  const DiscussionPreview.open(int this.students)
    : access = DiscussionAccess.open;

  const DiscussionPreview.notListed()
    : access = DiscussionAccess.notListed,
      students = null;

  const DiscussionPreview.removed()
    : access = DiscussionAccess.removed,
      students = null;
}
