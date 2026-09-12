import 'package:timezone/data/latest.dart' as data;
import 'package:timezone/timezone.dart' as tz;

/// Null means a floating wall-clock reminder in each device's local zone.
/// Fixed choices use IANA names, never offsets or EST/CST abbreviations.
const reminderTimeZones = <String, String>{
  'America/New_York': 'Eastern — New York',
  'America/Chicago': 'Central — Chicago',
  'America/Denver': 'Mountain — Denver',
  'America/Phoenix': 'Arizona — Phoenix',
  'America/Los_Angeles': 'Pacific — Los Angeles',
  'America/Anchorage': 'Alaska — Anchorage',
  'Pacific/Honolulu': 'Hawaii — Honolulu',
  'UTC': 'UTC',
};

bool _loaded = false;

tz.Location reminderLocation(String id) {
  if (!_loaded) {
    data.initializeTimeZones();
    _loaded = true;
  }
  return id == 'UTC' ? tz.UTC : tz.getLocation(id);
}

bool validReminderTimeZone(String? id) {
  if (id == null) return true;
  try {
    reminderLocation(id);
    return id.isNotEmpty;
  } on Object {
    return false;
  }
}

String reminderTimeZoneLabel(String? id) =>
    id == null ? 'Follow device timezone' : reminderTimeZones[id] ?? id;
