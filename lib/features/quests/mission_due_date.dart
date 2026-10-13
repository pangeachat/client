import 'package:flutter/material.dart';

import 'package:intl/intl.dart';
import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/date_time_extension.dart';

/// A Mission's soft due date as wall-clock time in the course's IANA
/// [timeZone], so everyone in the class reads the same deadline
/// (content-studio.instructions.md). No zone, or one this build does not know,
/// falls back to the viewer's own local time.
DateTime missionDueWallTime(DateTime dueAt, String? timeZone) {
  if (timeZone != null) {
    try {
      _ensureTimeZones();
      return tz.TZDateTime.from(dueAt, tz.getLocation(timeZone));
    } on tz.LocationNotFoundException {
      // silent-ok: an unknown zone name shows the date in the viewer's own
      // zone — the documented fallback for a course with no zone.
    }
  }
  return dueAt.toLocal();
}

/// "Due Oct 20, 5:00 PM" — the year is added only when it is not this year.
String missionDueLabel(BuildContext context, DateTime dueAt, String? timeZone) {
  final wall = missionDueWallTime(dueAt, timeZone);
  final locale = L10n.of(context).localeName;
  final date = wall.year == DateTime.now().year
      ? DateFormat.MMMd(locale).format(wall)
      : DateFormat.yMMMd(locale).format(wall);
  return L10n.of(
    context,
  ).missionDueDate(date, wall.localizedTimeOfDay(context));
}

bool _timeZonesReady = false;

void _ensureTimeZones() {
  if (_timeZonesReady) return;
  tzdata.initializeTimeZones();
  _timeZonesReady = true;
}
