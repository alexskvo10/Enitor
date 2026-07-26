# Enitor

A cross-platform app for daily tasks, goals, and productivity. No accounts,
no cloud — everything is stored locally on your device.

Platforms: **Windows**, **Android**. Single Flutter codebase.

## Features

- **Daily tasks**: start/end time, priority, tags, recurring tasks
  ("every Monday", "every 15th of the month", etc.), copying a day's task
  set to another day.
- **Built-in month calendar** with color-coded day markers (completed /
  partial / overdue), quick navigation between days.
- **Productivity ring** for the day, factoring in on-time completion.
- **Goals**: week / month / season / year, with deadlines, priority and
  tags; transferring unfinished goals requires confirmation (never silent).
- **Task transfer**: unfinished tasks from a past day don't just disappear —
  you're prompted to move them to today, with confirmation.
- **Statistics**: productivity and on-time charts for tasks and goals
  (day/week/month/year), task duration estimate accuracy, goal deadline
  compliance, breakdown by tags.
- **Pomodoro focus timer** (25 min work / 5 min break), tied to a specific
  task: a completed focus session is automatically counted toward the
  task's actual time spent.
- **Retrospective**: a day/period review — what worked, what didn't.
- **Profile and achievements**: daily streak, activity heatmap, day
  rating, achievements.
- **Backlog** — undated tasks waiting their turn.
- **Local notifications**: reminders for task start/end, "needs attention",
  overdue, goal reminders, quiet hours.
- **Localization**: Russian and English.
- **Dark theme**.

## Stack

| Layer                  | Technology                            |
|-------------------------|---------------------------------------|
| UI / app                | Flutter (Dart)                        |
| State management        | Riverpod                              |
| Navigation               | go_router                            |
| Local storage            | SharedPreferences (JSON)             |
| Charts                   | fl_chart                             |
| Calendar                 | table_calendar                       |
| Notifications             | flutter_local_notifications          |
| Localization              | flutter_localizations + intl (ru, en)|

Data is stored locally as JSON via `SharedPreferences` — no cloud sync, no
accounts. There's a manual backup export/import to a file (`file_picker`).

## Development setup

Detailed instructions in [docs/setup.md](docs/setup.md).

Quick start:
```bash
flutter pub get
flutter run -d windows     # run on Windows
flutter run -d <android>   # run on Android (device or emulator required)
```

## Architecture

Detailed description in [docs/architecture.md](docs/architecture.md).

In short: **feature-first** structure. Each feature (`today/`, `goals/`,
`stats/`, …) contains its own screens and providers. Shared layers —
`data/` (models + repositories), `core/` (theme, router, utils), `widgets/`
(reusable widgets), `services/` (notifications, quotes).

## Project structure

```
Enitor/
├── lib/
│   ├── main.dart                 # entry point
│   ├── app.dart                  # root app widget
│   ├── core/                     # theme, router, constants, utils
│   ├── l10n/                     # ru + en translations
│   ├── data/
│   │   ├── models/                # Task, Goal, DayStats, Achievement, ...
│   │   └── repositories/          # business logic over local storage
│   ├── features/                 # screens, grouped by feature
│   │   ├── today/                # daily task list + calendar
│   │   ├── backlog/               # undated tasks
│   │   ├── goals/                 # goals
│   │   ├── stats/                 # charts and analytics
│   │   ├── retro/                 # retrospective
│   │   ├── achievements/          # achievements
│   │   ├── profile/               # profile
│   │   ├── templates/             # day task-set templates
│   │   ├── search/                # search
│   │   ├── settings/              # settings, notifications
│   │   ├── help/                  # FAQ
│   │   └── about/                 # about screen
│   ├── widgets/                  # shared widgets (productivity ring, etc.)
│   └── services/                 # notifications, quotes
├── assets/
│   ├── fonts/
│   ├── icon/
│   └── quotes/                   # quote JSON files
├── test/
├── docs/
└── pubspec.yaml
```

## Tests

```bash
flutter test
```
