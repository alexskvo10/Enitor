<div align="center">

<img src="assets/icon/icon.png" width="112" height="112" alt="Enitor icon" />

# Enitor

**Staying out of your way isn't the goal. Getting better is.**

Tasks, goals, and honest productivity stats — cross-platform, fully local, no account required.

[![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Android-3B5BDB?style=flat-square)](#)
[![Flutter](https://img.shields.io/badge/built%20with-Flutter-02569B?style=flat-square&logo=flutter&logoColor=white)](#)
[![License: MIT](https://img.shields.io/badge/license-MIT-C26B45?style=flat-square)](LICENSE)
[![Languages](https://img.shields.io/badge/language-RU%20%7C%20EN-3FA66A?style=flat-square)](#)
[![Latest release](https://img.shields.io/github/v/release/alexskvo10/Enitor?style=flat-square&color=E8A23D)](https://github.com/alexskvo10/Enitor/releases/latest)

**[alexskvo10.github.io/Enitor](https://alexskvo10.github.io/Enitor/)** — screenshots, features and install instructions ([по-русски](https://alexskvo10.github.io/Enitor/ru/))

</div>

---

## Why Enitor

Most productivity apps aim for one thing: stay out of your way. Log a task, check it off, forget it. That's the premise Enitor argues with. A task list is only useful if it eventually shows you something about yourself: that you're more consistent than you think, that your estimates are always 20% short, that Tuesdays are where you fall off. Enitor is designed to surface that, not hide it behind a clean checklist.

Concretely, not as slogans:

- **A quote about discipline, not decoration.** Every day on the Today screen opens with a line pulled from a curated collection about showing up and improving in small increments ("Compare yourself to who you were yesterday, not to who someone else is today.") — not filler, the same idea the rest of the app is built around.
- **Streaks that are actually fair, so they're worth keeping.** Days with no tasks neither break nor pad your streak, and today (while still open) never breaks it either — a streak here means something, so chasing it is a legitimate motivator, not a guilt trip.
- **A year you can actually see.** A GitHub-style heatmap turns months of effort into one glance — the kind of feedback that makes consistency feel real instead of abstract.
- **A weekly retrospective that comes to you, instead of waiting to be found.** Monday evening by default, Enitor opens the past week for you: productivity against the week before, your best day, perfect days, the goals you'd actually set for that week, and whether your estimates got closer or further off. Five minutes that turn a busy week into something you learn from instead of just rolling into the next one. Nothing to log — it's all data you already have. No data for that week, no window.
- **Estimate accuracy that quietly makes you better at planning.** Planned vs. actual time, shown both by task count and by time weight, broken down by tag — most trackers never close this loop, so you never learn you're always 20% short.
- **Pomodoro that feeds that same loop.** A completed focus session logs itself as real time spent on the task — it's not a separate stopwatch gimmick, it's more data for the estimate-accuracy picture above.
- **Achievements that track real progress**, not just "opened the app" streaks — volume, consistency, punctuality, and milestones, so unlocking one actually means something happened, not that a day passed. Top-tier ones are hidden as "???" until you earn them, so there's always a next one worth finding out about.

And the fundamentals that make trusting it with your habits worthwhile:

- **Carry-over is never silent.** At the 4:00 AM day boundary Enitor *asks* what to carry over, creates a fresh copy on today, and leaves the original in its own day with a small arrow badge. History is never rewritten — your past stays exactly as it happened, which is what makes the stats above trustworthy in the first place.
- **The calendar won't guilt-trip you.** Days with no tasks are neutral, not red. An empty *future* day is blue, not red — there's a real difference between "you did nothing" and "you haven't gotten there yet."
- **The day starts at 4:00, not midnight.** If you're up late finishing something, your "today" doesn't flip under your feet at 00:00 — late-night hours still belong to the day that's ending, for the task list, for carry-over, and for the on-time stat alike. Finish a task scheduled until 2:00 AM at 1:30 and it counts as on time, not as "yesterday's task, done late." A task with no time set is the honest exception: its implicit deadline is the end of the calendar day, so finishing it after midnight does count as late.
- **A design system, not a coat of paint.** Warm "paper" surfaces, ink-colored shadows, a single sparing accent color, a spring-eased checkbox stroke that *draws itself* — every choice answers to one consistent metaphor ("a paper journal"), documented down to the hex code in [`docs/design-overview.md`](docs/design-overview.md).
- **Genuinely yours.** No account, no cloud, no telemetry. Everything lives in local storage; a manual export/import covers backups and device migration. The app also checks GitHub for new releases and updates itself — no store gatekeeping, no forced updates.
- **One codebase, two real platforms.** Windows and Android from a single Flutter codebase — not a phone app with a resized desktop wrapper, both get the same features, the same design, and fixes at the same time. Fully localized in Russian and English with an instant, no-restart language switch.

---

## Table of contents

- [Screenshots](#screenshots)
- [Installation](#installation)
- [Features](#features)
- [Design](#design)
- [Tech stack](#tech-stack)
- [Development setup](#development-setup)
- [Architecture](#architecture)
- [Project structure](#project-structure)
- [Tests](#tests)
- [License](#license)

---

## Screenshots

From the Windows build, on the generated demo data (`scripts/generate_demo_backup.dart`) rather than a real personal task list.

<table>
<tr>
  <td width="33%"><img src="docs/screenshots/windows/today.png" alt="Today screen" /><br/><sub>Today — a month at a glance with one colour dot per day, completion rings, and the day's remaining time budget</sub></td>
  <td width="33%"><img src="docs/screenshots/windows/goals.png" alt="Goals screen" /><br/><sub>Goals — week / month / season / year, with counter progress and a month's worth already closed out</sub></td>
  <td width="33%"><img src="docs/screenshots/windows/stats.png" alt="Statistics screen" /><br/><sub>Statistics — productivity against on-time, any granularity and range, plus estimate accuracy</sub></td>
</tr>
<tr>
  <td width="33%"><img src="docs/screenshots/windows/today_2.png" alt="Task list" /><br/><sub>The list itself — needs attention, unfinished, completed with time spent and a rating</sub></td>
  <td width="33%"><img src="docs/screenshots/windows/profile.png" alt="Profile screen" /><br/><sub>Profile — streak, all-time averages, year heatmap, achievements</sub></td>
  <td width="33%"><img src="docs/screenshots/windows/today_dark.png" alt="Today screen, dark theme" /><br/><sub>Dark theme — the same day on warm charcoal, not blue-grey</sub></td>
</tr>
</table>

<details>
<summary><b>More screens</b> — Pomodoro, carry-over, weekly retrospective, achievements, tag stats, settings</summary>

<table>
<tr>
  <td width="33%"><img src="docs/screenshots/windows/pomodoro_fuul.png" alt="Pomodoro timer" /><br/><sub>Pomodoro — the running session pins itself above the day, so the timer is never a screen you have to go find</sub></td>
  <td width="33%"><img src="docs/screenshots/windows/transfer.png" alt="Carry-over dialog" /><br/><sub>Carry-over at 4:00 — you pick what moves to today, nothing migrates silently</sub></td>
  <td width="33%"><img src="docs/screenshots/windows/week_summary.png" alt="Week summary" /><br/><sub>Weekly retrospective — the week against the one before, best day, goals set for that week, average day rating</sub></td>
</tr>
<tr>
  <td width="33%"><img src="docs/screenshots/windows/achievements.png" alt="Achievements" /><br/><sub>Achievements — 25 in all, some staying hidden until you unlock them</sub></td>
  <td width="33%"><img src="docs/screenshots/windows/tag_stats.png" alt="Tag statistics" /><br/><sub>Tag stats — completion and punctuality per tag, so you can see which areas you actually keep up with</sub></td>
  <td width="33%"><img src="docs/screenshots/windows/settings.png" alt="Settings" /><br/><sub>Settings — theme, paper texture, focus timer lengths, and every kind of notification toggled on its own</sub></td>
</tr>
<tr>
  <td colspan="3" align="center"><img src="docs/screenshots/windows/transfer_banner.png" width="33%" alt="Carry-over prompt at the day boundary" /><br/><sub>The other side of carry-over — caught right at the day boundary, the app asks about one task at a time. Note the unfinished task below it: the minutes the Pomodoro timer had already logged stay on it, done or not</sub></td>
</tr>
</table>

</details>

---

## Installation

Grab the latest build from [Releases](https://github.com/alexskvo10/Enitor/releases/latest) — no build tools required.

- **Android**: download the `.apk`, open it, and allow installation from this source when prompted (the app isn't distributed through Google Play, so Android will ask once). Requires Android 7.0+.
- **Windows**: download the `.zip`, extract it anywhere, and run `enitor.exe`. No installer, no admin rights needed.

After the first install, Enitor checks GitHub for new releases on its own (about once a day) and offers to update itself — you won't need to come back here for routine updates.

> **Windows: add `enitor.exe` to your antivirus's trusted list.** Enitor ships unsigned, so security suites that sandbox unknown applications (Kaspersky and 360 Total Security both do) may redirect its registry writes into a shadow copy. That matters for one specific thing: to show a notification, Windows looks the app up under `HKCU\Software\Classes\AppUserModelId\Dev.Enitor.App.Desktop`, which Enitor writes on startup. If that write is redirected, the entry never reaches the real registry — and Windows then **silently discards every scheduled notification**, with no error anywhere. The app can't detect this on its own, because reading the value back returns the sandboxed copy. Everything else keeps working, which makes it a confusing failure: reminders simply never arrive.

---

## Features

### Tasks
- A rotating quote from a curated collection about discipline and small daily progress opens the Today screen — not a widget nobody asked for, the same idea the rest of the app is built around.
- Start/end time, priority, tags, sub-tasks (checklist), or a numeric counter ("drink 5 glasses of water") — partial progress counts honestly toward productivity.
- Recurring tasks — by weekday, by day of month, or every N days — with a choice of how far ahead to generate.
- Copy a whole day's task set to another day, or save it as a reusable **template**.
- Global search across task titles, descriptions, and tags.

### Goals
- Four periods — week, month, season, year — with an optional deadline.
- A goal can be a checkbox, a counter/quota, or a checklist, and quota goals can auto-track linked tasks (e.g. "10 workouts this month").
- Priority and tags work the same way as for tasks, with dedicated tag statistics.
- Carrying an unfinished goal into the next period is one tap — always a copy, never a silent edit of the original.

### Carry-over, 4:00 rollover, and the backlog
- Unfinished tasks/goals from a past day are offered for carry-over, not force-moved — a top banner if the app is open, a catch-up checklist on next launch if it wasn't.
- If something is carried over and left undone *again*, it moves to the **backlog** instead of cluttering today's list — nothing is ever silently dropped.

### Statistics
- Productivity and on-time charts (day/week/month/year) for both tasks and goals, with a composite "best day/period" score that rewards a busy productive day over a single 100%-complete task.
- **Estimate accuracy**: planned vs. actual time, median-based, shown both by task count and by time weight, broken down by task size and by tag.
- **Goal deadline compliance** and tag-level breakdowns for both tasks and goals.

### Pomodoro
- Focus then break, tied to a specific task. Switching tabs doesn't reset the countdown, and a completed session is logged straight into the task's actual time.
- Both lengths are configurable (25/5 by default, because the classic numbers fit plenty of people but not everyone). A change takes effect from the next stretch — a running timer keeps the length it started with, so the time logged is always the time actually worked.
- Next to the setting sits a short guide on picking those numbers: where to start by the kind of work you do, how to read your own reaction at the bell, and what a break is actually for. Its starting points are tappable, so reading "45/10 for work with a warm-up" and setting it are the same gesture. Also reachable from Help / FAQ.

### Profile & achievements
- Daily streak (fair — empty days don't touch it), a GitHub-style year heatmap, a weekly retrospective with a productivity delta vs. last week, the goals set for that week, and estimate accuracy against the week before.
- The retrospective opens itself once a week — Monday 19:00 by default, day and time configurable — at the first launch after that moment, and waits for the next launch if you missed the evening. Monday rather than Sunday because the week has to be over first: measured on Sunday evening, your unfinished Sunday tasks land in the denominator and every week looks slightly worse than the last purely because of when it was measured.
- Optional daily mood/quality rating that feeds the weekly summary — purely reflective, it never affects productivity numbers.
- Achievement badges for volume, streaks, punctuality, and milestones; top-tier ones stay hidden as "???" until unlocked.

### Notifications
- Per-task start/end reminders, "needs attention," and overdue nudges, plus goal reminders, a morning plan, an evening review prompt, a week-summary nudge (Monday 19:00 by default, day and time configurable), and quiet hours — every kind toggled independently in Settings.
- The backlog gets its own nudge — twice a week for tasks, once a month for goals, on the 1st. It's the one place in the app that never spoke up for itself: things land there when they fall out of a day, and then go quiet until you happen to look.
- Nothing fires into an empty day. The "don't forget your tasks" nudges are scheduled only for days that actually have unfinished tasks and say how many; the backlog nudges stay quiet when the backlog is empty; the carry-over reminder stays quiet when there's nothing to carry over; the week summary skips a week with no data. A notification you can safely ignore is one that devalues every other notification the app sends.
- The one thing off by default is the carry-over reminder — it's pinned to the 4:00 day rollover, which puts it outside quiet hours, and unfinished items greet you in a dialog at the next launch anyway.
- On Windows, if no notification ever arrives, see the antivirus note under [Installation](#installation) — a sandboxing security suite is the usual cause.

### Data & updates
- 100% local storage, no account, no telemetry. Manual JSON export/import for backups and moving between devices, plus an automatic backup the app keeps on its own and restores after a clean reinstall.
- Settings can be reset to their defaults without touching your data, and there's a full data wipe for starting over — the wipe clears the automatic backup too, so it offers to export and delete in one step, and only deletes if the file actually got saved.
- Built-in self-update: checks GitHub Releases (throttled to once a day automatically, or on demand), shows the changelog, and installs itself — the system installer on Android, an automatic relaunch on Windows.

### Personalization
- Light / dark / system theme, three background styles (plain, paper grain, dot grid) with an optional vignette.
- Full Russian and English localization, switchable instantly without restarting.
- Desktop keyboard shortcuts (`Ctrl+N` to create, `Enter`/`Esc`/`Tab` in forms and dialogs).

---

## Design

The design follows the same idea as the feature set above: stay quiet everywhere so a task list doesn't become another source of noise, and spend that restraint on the few moments actually worth noticing.

Enitor isn't styled with default Material widgets — it follows a single, deliberate visual language called **"Living Paper"**: warm paper surfaces instead of stark white, ink-colored shadows instead of cold Material elevation, one sparing accent color instead of a rainbow of status colors, a thin 4px stripe plus a light background tint instead of a solid, fully-saturated fill so a busy list doesn't turn into a wall of colored blocks, and calm, human copy on empty/error states instead of alarming system text. Motion follows the same restraint: ordinary transitions use a calm, no-overshoot curve, and the "alive" spring-eased moments — a checkbox stroke that *draws itself*, a productivity ring that catches up with a slight overshoot, an achievement popup that pops and scatters sparks — are reserved specifically for finishing a task, hitting a streak, or unlocking a badge. The reward is real, but it only shows up when you've actually earned it.

Every color, timing, and component is documented — not as marketing copy, but as an actual spec — in [`docs/design-overview.md`](docs/design-overview.md).

---

## Tech stack

| Layer                | Technology                                    |
|-----------------------|-----------------------------------------------|
| UI / app               | Flutter (Dart)                                |
| State management        | Riverpod                                      |
| Navigation               | go_router                                    |
| Local storage             | SharedPreferences (JSON)                    |
| Charts                     | fl_chart                                    |
| Calendar                    | table_calendar                             |
| Notifications                 | flutter_local_notifications + timezone   |
| Self-update                     | GitHub Releases API + `archive`/`http`  |
| Localization                      | flutter_localizations + intl (ru, en) |

Data is stored locally as JSON via `SharedPreferences` — no cloud sync, no accounts. A manual backup export/import (`file_picker`) covers device migration and safety nets.

---

## Development setup

Building from source (not required just to use the app — see [Installation](#installation) for that). Detailed instructions in [docs/setup.md](docs/setup.md).

```bash
flutter pub get
flutter run -d windows     # run on Windows
flutter run -d <android>   # run on Android (device or emulator required)
```

---

## Architecture

Detailed description in [docs/architecture.md](docs/architecture.md).

In short: **feature-first** structure. Each feature (`today/`, `goals/`,
`stats/`, …) contains its own screens and providers. Shared layers —
`data/` (models + repositories), `core/` (theme, router, utils), `widgets/`
(reusable widgets), `services/` (notifications, updates).

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
│   │   ├── help/                  # FAQ + the focus-length guide
│   │   └── about/                 # about screen
│   ├── widgets/                  # shared widgets (productivity ring, etc.)
│   └── services/                 # notifications, updates
├── assets/
│   ├── fonts/
│   ├── icon/
│   ├── quotes/                   # quote JSON files
│   └── sounds/                   # Pomodoro chime
├── test/
├── docs/
└── pubspec.yaml
```

## Tests

```bash
flutter test
```

---

## License

[MIT](LICENSE) © alexskvo10
