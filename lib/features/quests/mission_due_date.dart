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
      final location = tz.getLocation(_currentZoneIds[timeZone] ?? timeZone);
      return tz.TZDateTime.from(dueAt, location);
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

/// Old IANA ids that browsers still offer (Chrome's Intl names these zones
/// by them, and the dashboard saves the name the teacher's browser gives),
/// mapped to the current ids this app's zone data carries. The data ships
/// only current ids, so without this a course in India, Nepal, Vietnam,
/// Ukraine or Argentina would show its due dates in each viewer's own zone.
const _currentZoneIds = {
  'Africa/Asmera': 'Africa/Asmara',
  'America/Buenos_Aires': 'America/Argentina/Buenos_Aires',
  'America/Catamarca': 'America/Argentina/Catamarca',
  'America/Coral_Harbour': 'America/Atikokan',
  'America/Cordoba': 'America/Argentina/Cordoba',
  'America/Indianapolis': 'America/Indiana/Indianapolis',
  'America/Jujuy': 'America/Argentina/Jujuy',
  'America/Louisville': 'America/Kentucky/Louisville',
  'America/Mendoza': 'America/Argentina/Mendoza',
  'Asia/Calcutta': 'Asia/Kolkata',
  'Asia/Katmandu': 'Asia/Kathmandu',
  'Asia/Saigon': 'Asia/Ho_Chi_Minh',
  'Atlantic/Faeroe': 'Atlantic/Faroe',
  'Europe/Kiev': 'Europe/Kyiv',
  'Pacific/Ponape': 'Pacific/Pohnpei',
  'Pacific/Truk': 'Pacific/Chuuk',
};

bool _timeZonesReady = false;

void _ensureTimeZones() {
  if (_timeZonesReady) return;
  tzdata.initializeTimeZones();
  _timeZonesReady = true;
}
