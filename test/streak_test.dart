import 'package:flutter_test/flutter_test.dart';
import 'package:rada/domain/streak.dart';

DateTime d(int day) => DateTime(2026, 7, day);

void main() {
  test('empty log = 0 streak', () {
    expect(currentStreak({}, 25, today: d(10)), 0);
  });

  test('today met counts immediately', () {
    expect(currentStreak({d(10): 30}, 25, today: d(10)), 1);
  });

  test('unbroken run counts back', () {
    final m = {d(7): 25, d(8): 40, d(9): 25, d(10): 30};
    expect(currentStreak(m, 25, today: d(10)), 4);
  });

  test('today not yet met does not break streak', () {
    final m = {d(8): 25, d(9): 25};
    expect(currentStreak(m, 25, today: d(10)), 2);
  });

  test('one grace day per week survives', () {
    // 6,7 met · 8 missed (grace) · 9,10 met — same ISO week
    final m = {d(6): 25, d(7): 25, d(9): 25, d(10): 25};
    expect(currentStreak(m, 25, today: d(10)), 4);
  });

  test('two misses in one week break the streak', () {
    // 6 met · 7 missed · 8 missed · 9,10 met (all same ISO week: 6-12 Jul 2026)
    final m = {d(6): 25, d(9): 25, d(10): 25};
    expect(currentStreak(m, 25, today: d(10)), 2);
  });

  test('below-goal minutes do not count', () {
    final m = {d(9): 10, d(10): 30};
    // 9th under goal -> grace; 8th empty -> break. Only today counts... plus
    // nothing before. Streak = 1.
    expect(currentStreak(m, 25, today: d(10)), 1);
  });
}
