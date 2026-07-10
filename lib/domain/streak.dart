/// Streak rules (spec §8.1): a day counts if logged minutes >= daily goal.
/// One grace day per ISO week — the streak survives a single miss.
library;

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// ISO week key like '2026-W28'.
String isoWeekKey(DateTime date) {
  final thursday = date.add(Duration(days: 3 - ((date.weekday + 6) % 7)));
  final firstJan = DateTime(thursday.year, 1, 1);
  final week = 1 + (thursday.difference(firstJan).inDays ~/ 7);
  return '${thursday.year}-W$week';
}

/// [minutesByDay]: minutes studied per calendar day.
/// Returns current streak length in days, counting back from [today]
/// (today itself counts if goal already met, otherwise it is skipped
/// without breaking the streak — the day isn't over yet).
int currentStreak(Map<DateTime, int> minutesByDay, int goalMinutes,
    {DateTime? today}) {
  final now = _day(today ?? DateTime.now());
  bool met(DateTime d) => (minutesByDay[_day(d)] ?? 0) >= goalMinutes;

  var streak = 0;
  var d = now;
  final graceUsed = <String>{};

  // Today: pending, not a miss.
  if (met(d)) {
    streak++;
  }
  d = d.subtract(const Duration(days: 1));

  while (true) {
    if (met(d)) {
      streak++;
    } else {
      final week = isoWeekKey(d);
      if (graceUsed.contains(week)) break;
      graceUsed.add(week);
      // grace day: doesn't increment, doesn't break
    }
    d = d.subtract(const Duration(days: 1));
    if (now.difference(d).inDays > 3650) break; // sanity bound
  }
  return streak;
}
