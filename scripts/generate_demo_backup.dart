// One-off tool: generates a fictional-but-presentable Enitor backup file for
// taking real in-app screenshots (README needs visuals, but we don't want to
// expose anyone's real personal task list). Uses the actual model classes so
// the JSON shape always matches what the app expects.
//
// Run: dart run scripts/generate_demo_backup.dart
// Then in the app: Settings -> Data -> Import from file, pick the output.
//
// IMPORTANT: "today" is baked in as the date this script is run. Import the
// file the same day, or the Today screen will show an empty/mismatched day.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:enitor/data/models/day_stats.dart';
import 'package:enitor/data/models/goal.dart';
import 'package:enitor/data/models/task.dart';
import 'package:enitor/data/models/user_profile.dart';

final _rand = Random(7);
DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

int _seq = 0;
String _id(String prefix) => '$prefix-${_seq++}';

const _workTitles = [
  'Reply to client emails',
  'Team standup',
  'Quarterly report draft',
  'Review pull requests',
  'Prep slides for Monday',
  'Sync with design team',
  'Fix onboarding bug',
  'Write release notes',
  'Update project roadmap',
  '1:1 with manager',
];
const _healthTitles = [
  'Morning run',
  'Gym: leg day',
  'Yoga session',
  'Meal prep',
  'Evening walk',
  'Stretch routine',
];
const _personalTitles = [
  'Call mom',
  'Grocery run',
  'Pay utility bills',
  'Clean the apartment',
  'Water the plants',
  'Plan weekend trip',
];
const _learningTitles = [
  'Read 20 pages',
  'Finish course chapter',
  'Practice Spanish',
  'Watch design talk',
];

String _pick(List<String> pool) => pool[_rand.nextInt(pool.length)];

class _DayPlan {
  _DayPlan(this.tasks, this.stats);
  final List<Task> tasks;
  final DayStats stats;
}

/// Same rule the app uses: a task with a time is on time if it was closed
/// before its end, an untimed one counts as on time whenever it's done.
bool _isOnTime(Task t) {
  if (!t.isCompleted) return false;
  if (t.endMinutes == null) return true;
  final m = t.completedAt!.hour * 60 + t.completedAt!.minute;
  return m <= t.endMinutes!;
}

/// Builds one day's tasks + the matching DayStats, using the exact same
/// formula as StatsRepository.recompute so the numbers are always consistent
/// with the task list.
_DayPlan _buildDay(DateTime day, {required double targetProductivity}) {
  final n = 2 + _rand.nextInt(3); // 2..4 tasks
  final tasks = <Task>[];
  final pools = [_workTitles, _healthTitles, _personalTitles, _learningTitles];
  final tags = ['work', 'health', 'personal', 'learning'];

  for (var i = 0; i < n; i++) {
    final poolIdx = _rand.nextInt(pools.length);
    final title = _pick(pools[poolIdx]);
    final hasTime = _rand.nextDouble() < 0.7;
    final startH = 7 + _rand.nextInt(12);
    final start = hasTime ? startH * 60 + (_rand.nextBool() ? 0 : 30) : null;
    final end = hasTime ? start! + 30 + _rand.nextInt(4) * 15 : null;

    final willComplete = _rand.nextDouble() < targetProductivity;
    DateTime? completedAt;
    if (willComplete) {
      final complMin = end != null
          ? (end - 10 + _rand.nextInt(15)).clamp(0, 23 * 60)
          : 12 * 60;
      completedAt =
          DateTime(day.year, day.month, day.day, complMin ~/ 60, complMin % 60);
    }

    final hasEstimate = _rand.nextDouble() < 0.45;
    final estimated = hasEstimate ? 20 + _rand.nextInt(9) * 10 : null;
    final actual = (hasEstimate && willComplete)
        ? (estimated! + (_rand.nextInt(21) - 10)).clamp(10, 300)
        : null;
    final quality = (willComplete && _rand.nextDouble() < 0.35)
        ? 7 + _rand.nextInt(4)
        : null;
    final priority = _rand.nextDouble() < 0.15
        ? TaskPriority.high
        : (_rand.nextDouble() < 0.25 ? TaskPriority.medium : TaskPriority.none);

    tasks.add(Task(
      id: _id('task'),
      title: title,
      date: day,
      createdAt: day,
      updatedAt: completedAt ?? day,
      order: i,
      startMinutes: start,
      endMinutes: end,
      estimatedMinutes: estimated,
      actualMinutes: actual,
      completedAt: completedAt,
      quality: quality,
      priority: priority,
      tags: [tags[poolIdx]],
    ));
  }

  final completed = tasks.where((t) => t.isCompleted).toList();
  final onTimeCount = completed.where(_isOnTime).length;
  final fraction = tasks.fold<double>(0, (s, t) => s + t.completionFraction);

  return _DayPlan(
    tasks,
    DayStats(
      date: day,
      totalTasks: tasks.length,
      completedTasks: completed.length,
      completedFraction: fraction,
      onTimeCount: onTimeCount,
      lateCount: completed.length - onTimeCount,
      updatedAt: day,
    ),
  );
}

void main() {
  final today = _dateOnly(DateTime.now());
  final allTasks = <Task>[];
  final allStats = <DayStats>[];

  // 41 days of varied history (day -49 .. -9): believable mix, not a
  // suspicious wall of 100%s — this is what makes the year heatmap and
  // achievements look earned rather than staged. Two "zero" tiers on
  // purpose: no tasks at all (neutral, gray) is a different thing from
  // tasks that all went undone (an actual bad/red day) — the calendar
  // colors them differently, so the demo data should have both.
  const guaranteedBadDayOffset = 12;
  for (var offset = 49; offset >= 9; offset--) {
    if (offset == guaranteedBadDayOffset) continue; // handled explicitly below
    final day = today.subtract(Duration(days: offset));
    final roll = _rand.nextDouble();
    if (roll < 0.08) continue; // neutral day, no tasks at all
    final target = roll < 0.18
        ? 0.0 // bad day: tasks existed, none got done
        : roll < 0.35
            ? 0.55 // rough day
            : roll < 0.78
                ? 0.9 // solid day
                : 1.0; // great day
    final plan = _buildDay(day, targetProductivity: target);
    allTasks.addAll(plan.tasks);
    allStats.add(plan.stats);
  }

  // Guaranteed bad day, not left to chance: mid-July, safely inside the
  // calendar month you're actually looking at when you take the screenshot.
  final guaranteedBadDay =
      today.subtract(const Duration(days: guaranteedBadDayOffset));
  final badPlan = _buildDay(guaranteedBadDay, targetProductivity: 0.0);
  allTasks.addAll(badPlan.tasks);
  allStats.add(badPlan.stats);

  // Last 8 days before today: a clean streak, so Profile/heatmap has
  // something satisfying to show.
  for (var offset = 8; offset >= 1; offset--) {
    final day = today.subtract(Duration(days: offset));
    final plan = _buildDay(day, targetProductivity: 1.0);
    allTasks.addAll(plan.tasks);
    allStats.add(plan.stats);
  }

  // Today: a hand-picked, full-day spread so it looks right regardless of
  // what time of day the screenshot is actually taken.
  final todayTasks = [
    Task(
      id: _id('task'),
      title: 'Morning run',
      date: today,
      createdAt: today,
      updatedAt: today,
      order: 0,
      startMinutes: 6 * 60 + 30,
      endMinutes: 7 * 60 + 15,
      completedAt: DateTime(today.year, today.month, today.day, 7, 10),
      estimatedMinutes: 45,
      actualMinutes: 40,
      quality: 9,
      tags: const ['health'],
    ),
    Task(
      id: _id('task'),
      title: 'Reply to client emails',
      date: today,
      createdAt: today,
      updatedAt: today,
      order: 1,
      startMinutes: 9 * 60,
      endMinutes: 9 * 60 + 30,
      completedAt: DateTime(today.year, today.month, today.day, 9, 25),
      tags: const ['work'],
    ),
    Task(
      id: _id('task'),
      title: 'Team standup',
      date: today,
      createdAt: today,
      updatedAt: today,
      order: 2,
      startMinutes: 9 * 60 + 30,
      endMinutes: 9 * 60 + 45,
      completedAt: DateTime(today.year, today.month, today.day, 9, 44),
      tags: const ['work'],
    ),
    Task(
      id: _id('task'),
      title: 'Deep work: quarterly report',
      date: today,
      createdAt: today,
      updatedAt: today,
      order: 3,
      startMinutes: 10 * 60,
      endMinutes: 12 * 60,
      estimatedMinutes: 120,
      priority: TaskPriority.high,
      tags: const ['work'],
    ),
    // Closed after its own end time — the one late task of the day, so the
    // "on time" ring isn't a flat 100% either.
    Task(
      id: _id('task'),
      title: 'Physio stretches',
      date: today,
      createdAt: today,
      updatedAt: today,
      order: 4,
      startMinutes: 12 * 60 + 30,
      endMinutes: 13 * 60,
      completedAt: DateTime(today.year, today.month, today.day, 13, 20),
      estimatedMinutes: 30,
      actualMinutes: 35,
      tags: const ['health'],
    ),
    Task(
      id: _id('task'),
      title: 'Send the studio invoice',
      date: today,
      createdAt: today,
      updatedAt: today,
      order: 5,
      startMinutes: 14 * 60,
      endMinutes: 14 * 60 + 30,
      completedAt: DateTime(today.year, today.month, today.day, 14, 12),
      estimatedMinutes: 30,
      actualMinutes: 15,
      tags: const ['work'],
    ),
    // A counter and a checklist, both mid-progress: they contribute fractions
    // rather than 0 or 1, which is exactly what the ring's "7.3 / 12" label
    // and its partially filled arc are there to show.
    Task(
      id: _id('task'),
      title: 'Drink 8 glasses of water',
      date: today,
      createdAt: today,
      updatedAt: today,
      order: 6,
      targetCount: 8,
      progressCount: 5,
      tags: const ['health'],
    ),
    Task(
      id: _id('task'),
      title: 'Prep the Thursday demo',
      date: today,
      createdAt: today,
      updatedAt: today,
      order: 7,
      startMinutes: 15 * 60,
      endMinutes: 16 * 60 + 30,
      estimatedMinutes: 90,
      priority: TaskPriority.medium,
      subtasks: [
        SubTask(id: _id('sub'), title: 'Pull the numbers', done: true),
        SubTask(id: _id('sub'), title: 'Draft the slides', done: true),
        SubTask(id: _id('sub'), title: 'Run through it once', done: false),
      ],
      tags: const ['work'],
    ),
    Task(
      id: _id('task'),
      title: 'Water the plants',
      date: today,
      createdAt: today,
      updatedAt: today,
      order: 8,
      completedAt: DateTime(today.year, today.month, today.day, 8, 40),
      tags: const ['personal'],
    ),
    Task(
      id: _id('task'),
      title: 'Grocery run',
      date: today,
      createdAt: today,
      updatedAt: today,
      order: 9,
      startMinutes: 17 * 60 + 30,
      endMinutes: 18 * 60 + 15,
      estimatedMinutes: 45,
      tags: const ['personal'],
    ),
    Task(
      id: _id('task'),
      title: 'Call mom',
      date: today,
      createdAt: today,
      updatedAt: today,
      order: 10,
      priority: TaskPriority.medium,
      tags: const ['personal'],
    ),
    Task(
      id: _id('task'),
      title: 'Read 20 pages',
      date: today,
      createdAt: today,
      updatedAt: today,
      order: 11,
      tags: const ['learning'],
    ),
  ];
  allTasks.addAll(todayTasks);
  // Counted the same way the app does — through completionFraction and the
  // on-time rule — instead of "completed == fraction, everything on time".
  // With a counter and a checklist in the list those two would now disagree
  // with what the screen itself shows.
  final todayCompleted = todayTasks.where((t) => t.isCompleted).toList();
  final todayOnTime = todayCompleted.where(_isOnTime).length;
  allStats.add(DayStats(
    date: today,
    totalTasks: todayTasks.length,
    completedTasks: todayCompleted.length,
    completedFraction:
        todayTasks.fold<double>(0, (s, t) => s + t.completionFraction),
    onTimeCount: todayOnTime,
    lateCount: todayCompleted.length - todayOnTime,
    updatedAt: today,
  ));

  // A couple of upcoming days, lightly populated (calendar shows them blue,
  // not red — nothing to complete yet).
  for (var offset = 1; offset <= 2; offset++) {
    final day = today.add(Duration(days: offset));
    allTasks.add(Task(
      id: _id('task'),
      title: _pick(_workTitles),
      date: day,
      createdAt: today,
      updatedAt: today,
      startMinutes: 10 * 60,
      endMinutes: 11 * 60,
      tags: const ['work'],
    ));
  }

  // ── Goals ──────────────────────────────────────────────────────────────
  final (seasonYear, seasonIdx) = seasonOf(today);
  final goals = <Goal>[
    Goal(
      id: _id('goal'),
      period: GoalPeriod.week,
      year: today.year,
      weekStart: today.subtract(Duration(days: today.weekday - 1)),
      title: 'Work out 4 times this week',
      targetCount: 4,
      manualProgress: 3,
      createdAt: today,
      updatedAt: today,
      tags: const ['health'],
    ),
    Goal(
      id: _id('goal'),
      period: GoalPeriod.month,
      year: today.year,
      month: today.month,
      title: 'Launch the new landing page',
      priority: TaskPriority.high,
      createdAt: today,
      updatedAt: today,
      tags: const ['work'],
    ),
    Goal(
      id: _id('goal'),
      period: GoalPeriod.month,
      year: today.year,
      month: today.month,
      title: 'Read 2 books',
      targetCount: 2,
      manualProgress: 1,
      createdAt: today,
      updatedAt: today,
      tags: const ['learning'],
    ),
    // Three more for the current month, so the Goals screen isn't two lines
    // and its ring lands mid-arc instead of at a quarter — that's where the
    // gradient actually has something to show.
    Goal(
      id: _id('goal'),
      period: GoalPeriod.month,
      year: today.year,
      month: today.month,
      title: 'Publish 4 blog posts',
      targetCount: 4,
      manualProgress: 3,
      createdAt: DateTime(today.year, today.month, 1),
      updatedAt: today,
      tags: const ['work'],
    ),
    Goal(
      id: _id('goal'),
      period: GoalPeriod.month,
      year: today.year,
      month: today.month,
      title: 'Refresh the portfolio site',
      completed: true,
      completedAt: today.subtract(const Duration(days: 3)),
      createdAt: DateTime(today.year, today.month, 1),
      updatedAt: today.subtract(const Duration(days: 3)),
      tags: const ['work'],
    ),
    Goal(
      id: _id('goal'),
      period: GoalPeriod.month,
      year: today.year,
      month: today.month,
      title: 'Set up the summer training plan',
      completed: true,
      completedAt: today.subtract(const Duration(days: 9)),
      createdAt: DateTime(today.year, today.month, 1),
      updatedAt: today.subtract(const Duration(days: 9)),
      tags: const ['health'],
    ),
    // Closed after its own deadline — keeps the goals' "on time" ring off a
    // flat 100%, the same way one late task does on the Today screen.
    Goal(
      id: _id('goal'),
      period: GoalPeriod.month,
      year: today.year,
      month: today.month,
      title: 'Renew the passport',
      deadline: today.subtract(const Duration(days: 5)),
      completed: true,
      completedAt: today.subtract(const Duration(days: 2)),
      createdAt: DateTime(today.year, today.month, 1),
      updatedAt: today.subtract(const Duration(days: 2)),
      tags: const ['personal'],
    ),
    Goal(
      id: _id('goal'),
      period: GoalPeriod.season,
      year: seasonYear,
      season: seasonIdx,
      title: 'Learn the basics of woodworking',
      subtasks: [
        SubTask(id: _id('sub'), title: 'Watch beginner course', done: true),
        SubTask(id: _id('sub'), title: 'Buy basic tools', done: true),
        SubTask(id: _id('sub'), title: 'Build a small shelf', done: false),
      ],
      createdAt: today,
      updatedAt: today,
      tags: const ['personal'],
    ),
    Goal(
      id: _id('goal'),
      period: GoalPeriod.year,
      year: today.year,
      title: 'Run a half marathon',
      deadline: DateTime(today.year, 10, 1),
      createdAt: today,
      updatedAt: today,
      tags: const ['health'],
    ),
    // Past, already achieved — for goalsDone / achievements and a bit of
    // completed-goal color variety.
    Goal(
      id: _id('goal'),
      period: GoalPeriod.month,
      year: today.month == 1 ? today.year - 1 : today.year,
      month: today.month == 1 ? 12 : today.month - 1,
      title: 'Set up a home budget',
      completed: true,
      completedAt: today.subtract(const Duration(days: 20)),
      createdAt: today.subtract(const Duration(days: 40)),
      updatedAt: today.subtract(const Duration(days: 20)),
      tags: const ['personal'],
    ),
    Goal(
      id: _id('goal'),
      period: GoalPeriod.week,
      year: today.year,
      weekStart: today.subtract(Duration(days: today.weekday - 1 + 7)),
      title: 'Declutter the garage',
      completed: true,
      completedAt: today.subtract(const Duration(days: 6)),
      createdAt: today.subtract(const Duration(days: 10)),
      updatedAt: today.subtract(const Duration(days: 6)),
      tags: const ['personal'],
    ),
  ];

  // ── Day ratings (a handful, mostly good, a few 10s) ─────────────────────
  final dayRatings = <String, int>{};
  for (var offset = 2; offset <= 30; offset += _rand.nextInt(3) + 1) {
    final day = today.subtract(Duration(days: offset));
    final key = DateTime(day.year, day.month, day.day).toIso8601String();
    dayRatings[key] = 6 + _rand.nextInt(4); // 6..9
  }
  for (final offset in [3, 7, 15, 22]) {
    final day = today.subtract(Duration(days: offset));
    final key = DateTime(day.year, day.month, day.day).toIso8601String();
    dayRatings[key] = 10;
  }

  // ── User profile (backdated so "days using" looks lived-in) ─────────────
  final profile = UserProfile(
    startedAt: today.subtract(const Duration(days: 52)),
    updatedAt: today,
  );

  // ── Assemble in the exact shape BackupService.restoreFromJson expects ───
  final data = <String, String>{
    'tasks': jsonEncode(allTasks.map((t) => t.toJson()).toList()),
    'goals': jsonEncode(goals.map((g) => g.toJson()).toList()),
    'day_stats': jsonEncode(allStats.map((s) => s.toJson()).toList()),
    'day_ratings': jsonEncode(dayRatings),
    'user_profile': jsonEncode(profile.toJson()),
    // Import restores every key it's given, so the seed pins the interface
    // language too: the screenshots in the README and on the site are English,
    // and remembering to switch it by hand before each session is how a
    // Russian screenshot ends up in an English gallery.
    //
    // 2 is AppLocaleOption.en — the index, because this script runs under
    // plain `dart run` and importing the controller would drag Flutter (and
    // its FFI) in, which the standalone compiler chokes on. If that enum ever
    // gains a member before `en`, this number moves with it.
    'app_locale': jsonEncode({'option': 2}),
  };

  final payload = {
    'app': 'todo',
    'format': 1,
    'exportedAt': DateTime.now().toIso8601String(),
    'platform': 'demo',
    'data': data,
  };

  final outDir = Directory('dist');
  if (!outDir.existsSync()) outDir.createSync(recursive: true);
  final outFile = File('dist/enitor-demo-seed.json');
  outFile
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(payload));

  stdout.writeln('Wrote ${outFile.path}');
  stdout.writeln('Tasks: ${allTasks.length}, Goals: ${goals.length}, '
      'Days with stats: ${allStats.length}, Day ratings: ${dayRatings.length}');
  stdout.writeln(
      '"Today" baked in as: ${today.toIso8601String().split('T').first}'
      ' — import the same day.');
}
