# Architecture

## Principles

1. **Feature-first.** Code is grouped by feature, not by layer. Each feature (`today`, `goals`, `stats`, …) contains its own screens and providers. This makes code easy to find and whole features easy to remove.
2. **Thin widgets, thick repositories.** Widgets only describe the UI and subscribe to providers. All business logic lives in repositories.
3. **Riverpod as the single source of truth.** Providers are declared next to their feature (`*_providers.dart`) or in `data/repositories/`.
4. **Everything is local.** The app doesn't require an account and doesn't sync with a server — repositories only read/write on-device. The only way to move data to another device is a manual backup export/import.

## Layers

```
┌──────────────────────────────────────┐
│ UI (features/, widgets/)              │  ← ConsumerWidget, subscribes to providers
├──────────────────────────────────────┤
│ Providers (Riverpod)                  │  ← state + side effects
├──────────────────────────────────────┤
│ Repositories (data/repositories/)     │  ← business logic, calculations, transfer/backlog
├──────────────────────────────────────┤
│ Storage (SharedPreferences, JSON)     │  ← local storage
├──────────────────────────────────────┤
│ Services                              │  ← notifications, quotes
└──────────────────────────────────────┘
```

## Storage

Data (tasks, goals, daily stats, ring snapshots, achievements, profile,
settings) is serialized to JSON and stored via `SharedPreferences`. Each
repository (`task_repository.dart`, `goal_repository.dart`, …) is
responsible for serializing its own data area, caches state in memory, and
notifies providers on change.

Backup is a separate, manual feature: exporting the entire state to a
single JSON file and importing it back (`file_picker`). The magic string
`'app':'todo'` inside the backup file is a historical artifact, kept for
backward compatibility with older backups, and is not renamed as part of
the Enitor rebrand.

## Key models (as implemented, `lib/data/models/`)

- **Task** — a day's task: title, start/end time, priority, tags, recurrence
  rules (`RecurrenceRule`), transfer state (`transferDeclined`, etc.).
- **Goal** — a goal with period `week | month | season | year`, a deadline,
  priority, tags; stores daily progress snapshots to render charts
  retroactively.
- **DayStats** — aggregated daily statistics (how many tasks completed, on
  time, etc.), used by charts and the profile screen.
- **Achievement** — achievement state (unlocked or not, date).
- **UserProfile** — first-launch date, daily streak, cached weekly averages.
- **BacklogItem**, **DayTemplate**, **MotivationalQuote** — supporting models
  for the backlog, day templates, and quotes.

## Productivity calculation

- **Daily productivity** = share of completed tasks/goals for the day (a day
  with no tasks is excluded from averages).
- **On-time rate** — share of completions that were on time among all
  completions; a separate line on charts, distinct from the completion
  percentage.
- Exact formulas for specific metrics (best period, composite score, ring
  snapshots) live in the repository code (`goal_repository.dart`,
  `stats_repository.dart`); they've been tuned repeatedly and aren't
  duplicated here to avoid drift.

## Charts

`ProductivityChart` / `GoalProductivityChart` take a point granularity
(day/week/month/year) and a range, pull aggregated data from the
corresponding repository, and draw an `fl_chart` LineChart with straight
(non-smoothed) segments — the data is discrete, and smoothing produced
visual artifacts at period boundaries.

## Notifications

`NotificationService` on top of `flutter_local_notifications`: reminders for
task start/end, "needs attention", overdue, goal reminders, quiet hours. On
Windows (no native repeat support in the plugin), notifications are
rescheduled via an explicit loop several weeks ahead instead of
`matchDateTimeComponents`.

## Testing

- `test/` — unit tests for repositories and productivity/statistics
  calculations (the area most prone to invisible regressions).
- Run with `flutter test`.
