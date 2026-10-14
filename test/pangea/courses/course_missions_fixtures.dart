import 'package:matrix/matrix.dart';

import 'package:fluffychat/routes/chat/events/constants/pangea_event_types.dart';

/// Shared fixtures for the course's own copy (`pangea.course_missions`).
const kTeacher = '@teacher:fakeServer.notExisting';
const kStudent = '@student:fakeServer.notExisting';

int _eventCounter = 0;

/// Seat [type] as room state on [room], sent by [sender].
void putState(
  Room room,
  String type,
  Map<String, dynamic> content, {
  String sender = kTeacher,
}) => room.setState(
  Event(
    type: type,
    content: content,
    stateKey: '',
    senderId: sender,
    eventId: '\$${type}_${_eventCounter++}',
    originServerTs: DateTime.utc(2026, 10, 1),
    room: room,
  ),
);

/// The teacher at power level 100, the student at 0.
void putPowerLevels(Room room) => putState(room, EventTypes.RoomPowerLevels, {
  'users': {kTeacher: 100, kStudent: 0},
  'users_default': 0,
});

/// A copy content map: [missions] maps Can-Do id to its activity ids, in
/// order.
Map<String, dynamic> copyContent(
  Map<String, List<String>> missions, {
  int revision = 1,
  String? timeZone,
  Map<String, String> notes = const {},
  Map<String, String> dueAt = const {},
}) => {
  'version': 1,
  'revision': revision,
  'time_zone': ?timeZone,
  'missions': [
    for (final e in missions.entries)
      {
        'lo_id': e.key,
        'activity_ids': e.value,
        'note': ?notes[e.key],
        'due_at': ?dueAt[e.key],
      },
  ],
};

void putCopy(
  Room room,
  Map<String, List<String>> missions, {
  int revision = 1,
  String sender = kTeacher,
  String? timeZone,
  Map<String, String> notes = const {},
  Map<String, String> dueAt = const {},
}) => putState(
  room,
  PangeaEventTypes.courseMissions,
  copyContent(
    missions,
    revision: revision,
    timeZone: timeZone,
    notes: notes,
    dueAt: dueAt,
  ),
  sender: sender,
);
