# Enitor — "Living Paper". Full design (UI) description

This document describes Enitor's visual system (Flutter, Windows + Android) as it is actually implemented in code today. Not marketing copy — a technical design spec: exact colors, fonts, animation timings, component behavior.

---

## 1. Concept

**"Paper journal"** — not a swappable visual theme, but a principle that answers "why" for every visual decision:

- Background — not white, but warm paper (#F7F4EE), with subtle paper grain or a dot grid (bullet journal).
- Shadows — not cold bluish Material elevation, but warm "ink" shadows: a card looks "stuck onto" the paper rather than floating above it.
- Accent — a single one: warm terracotta "Clay" (#C26B45), used sparingly (quote drop cap, day header, streak icon, error/empty states) — never spread across the whole UI.
- Progress/motion — anywhere something "comes alive" (ring, checkbox, popup), a spring curve with a slight overshoot is used instead of a linear appearance — a "living", not mechanical, feel.
- Text — an accent serif typeface (Source Serif 4) for the day's quote and screen title, a "journal" touch that sets the app apart from a typical Material to-do list.

Dark theme — not an inversion, but a separate metaphor: "Night study", warm charcoal (not blue-black), with a brightened accent (otherwise the primary blue loses contrast on a dark background).

---

## 2. Color

### 2.1 Brand and accent

| Token | HEX | Purpose |
|---|---|---|
| `primary` | `#3B5BDB` | Brand — "ink blue" (fountain pen). Buttons, links, active states, light theme. |
| `primaryDark` | `#2F4BC4` | Darker shade of primary (pressed state, etc.) |
| `primarySoft` | `#93A7F5` | Dark-theme accent — intentionally brightened: dark blue lost contrast on the charcoal background. |
| `clay` | `#C26B45` | Second, sparing accent "Clay" — drop cap, day header, error/empty-state icons, achievement popup border. |

### 2.2 Surfaces

| Token | HEX | Theme |
|---|---|---|
| `background` | `#F7F4EE` | light — warm paper |
| `surface` | `#FFFFFF` | light — cards |
| `surfaceMuted` | `#EFEAE0` | light — toggle track, muted fills |
| `backgroundDark` | `#181613` | dark — warm charcoal (NOT blue-black) |
| `surfaceDarkElevated` | `#211E19` | dark — cards |
| `surfaceDarkMuted` | `#2A261F` | dark — toggle track, borders |

### 2.3 Text

| Token | HEX | Purpose |
|---|---|---|
| `textPrimary` | `#2A2722` | light — "warm ink", not pure black |
| `textSecondary` | `#7A7468` | light — secondary text |
| `textPrimaryDark` | `#ECE7DC` | dark — "cream", not pure white |
| `textSecondaryDark` | `#9B948A` | dark — secondary text |

### 2.4 Semantic

| Token | HEX | Purpose |
|---|---|---|
| `success` | `#3FA66A` | completed / success |
| `danger` | `#D65745` | delete / error / overdue |
| `warning` | `#E8A23D` | partially completed / warning |
| `warningGradient` | `#E8A23D → #CF7F28` | amber gradient for counter rings (not the default amber→orange) |
| `ringGradient` | `#3B5BDB → #6E86F0` | productivity ring arc gradient |
| `ringTrack` / `ringTrackDark` | `#E8E2D6` / `#332E26` | ring background track |

Project rule: **no "raw" `Colors.green/red/amber/blue`** — the whole UI was audited and moved to semantic palette tokens (see Part 2, item 7).

---

## 3. Typography

Three type roles, all fonts bundled offline (never fetched over the network):

| Role | Font | Where |
|---|---|---|
| UI text | **Inter** (Regular 400, Medium 500) | body, labels, navigation labels |
| Headings/numbers | **Manrope** (Regular, Bold 700; headline/title slots get w600–w800) | section headings, large numbers (ring percentages) |
| "Journal" accent | **Source Serif 4** (Regular, SemiBold 600, Bold 700, Italic) | AppBar title (23px, w600), day-quote drop cap and text (italic), app name on the About screen |

Day quote drop cap: first letter — Source Serif 4, 46px, w600, `clay` color, `height: 0.92`; the rest of the text — regular-size italic Source Serif 4.

---

## 4. Surfaces, shadows, shape

- Card corner radius — **16px**, popups — **24px**, chips/pills — **stadium (fully rounded)**.
- **`stickerShadow`** (regular card) — two layers: a contact shadow `blur 2 / offset (0,1) / alpha 0.05` + a diffuse one `blur 14 / offset (0,5) / alpha 0.055`, color — warm ink `#2A2722`, not gray/blue.
- **`raisedShadow`** (elevated surfaces — FAB, sheets, dialogs, toasts, achievement popup) — `blur 6 / offset (0,2) / alpha 0.07` + `blur 34 / offset (0,14) / alpha 0.10`.
- Card in dark theme: the shadow barely reads on charcoal → compensated with a `surfaceDarkMuted` border + `surfaceTintColor: transparent` (important: without this, Material 3 mixes a tonal overlay on top of the dark background).
- **State stripe**: instead of filling the whole task/goal tile with the status color, a thin 4px colored stripe on the left (danger/success/warning) + a subtle ~8% background tint. Transferred tasks — gray background, no stripe.

---

## 5. Motion system (curves and timings)

Two named curve tokens across the whole app:

- **`easeOut`** — `Cubic(0.22, 1, 0.36, 1)` — the standard smooth appearance/motion (toggle pill, dialog dismissal, ordinary transitions).
- **`spring`** — `Cubic(0.34, 1.56, 0.64, 1)` — a spring with a slight overshoot past 100%, for "living" accents (rings, checkbox, popups, toasts, achievements).

Key component timings:

| Effect | Duration | Curve |
|---|---|---|
| Period toggle (pill slides) | 240 ms | easeOut |
| Dialog: scale+fade entrance | 280 ms | spring |
| Dialog medallion icon ("pops in") | 90 ms delay + 520 ms (TweenSequence 70%/30%, easeOutBack→easeOut, 0.4→1.12→1.0) | — |
| Toast: slide up from bottom | 460 ms in / 260 ms out | spring / easeIn |
| Achievement popup: slide down from top | 650 ms | spring / easeIn (on close) |
| Achievement popup: medallion background pulse | 1100 ms, repeat-reverse | linear |
| Achievement popup: sparks (7, 34px radius) | synced with entrance × 1.6 | — |
| Achievement popup: auto-close | after 3600 ms, or swipe up / tap | — |
| Task checkbox: stroke drawing | 340 ms | easeOut |
| Checkbox: splash ring on completion | 460 ms, one-shot | linear (by alpha) |
| List card cascade reveal (StaggerReveal) | 280 ms per element, staggered by `index × 45 ms` (capped at 360 ms) | easeOut, fade + 10px upward offset |
| Productivity ring: arc catch-up | 1100 ms | spring (the number is clamped to the target — no reverse "jitter") |
| Task stripe tint cross-fade | 260 ms | ColorTween |
| "Paper" slide between tabs (Today/Goals/…) | 220 ms | Fade + Slide ±0.04 in the transition direction |

---

## 6. Background and "atmosphere"

A global `AppBackground` layer is drawn once beneath the whole app (Scaffold and AppBar are transparent), with three user-selectable styles (configurable in Settings):

1. **Smooth** — a flat theme color.
2. **Paper** (default) — a two-layer fine dot ripple (7px and 11px pitch, alpha 0.035–0.06) — reads as paper grain, no assets involved.
3. **Dots** — a regular 24px dot grid (bullet-journal aesthetic), alpha 0.11–0.13.

Optional **vignette**: in light theme — a subtle edge darkening (radial gradient, alpha up to 0.035); in dark theme — the opposite, a subtle center brightening. Doesn't intercept touch (`IgnorePointer`).

**Empty states** (`NotebookEmptyState`) — not a placeholder, but a "ruled page": horizontal notebook lines (37px pitch, alpha 0.12, theme accent color) + a doodle icon (usually clay, alpha 0.75) + calm copy.

**Error states** (`ErrorView`) — the same tonal logic: `cloud_off` icon, clay 0.75, "Couldn't load" text (no raw error text — it's scary and explains nothing to the user), an optional "Retry" button.

---

## 7. Component library

Reusable widgets with their own character — not bare system defaults:

- **`DrawCheckBox`** — a checkbox where the checkmark doesn't appear instantly but is "drawn" along its path (two segments, length computed geometrically for a constant-speed stroke), with an outline that cross-fades into a fill, and a splash ring on completion. The tap responds optimistically (instantly), without waiting for the data model.
- **`ProductivityRing`** — a `CustomPainter` progress ring: a symmetric `SweepGradient` (color→light→same color) so a full circle has no visible seam; a soft blurred glow beneath the arc; the center number doesn't jump back during the spring overshoot.
- **`GlowFab`** — an extended FAB with a soft colored halo beneath it (a negative-spread shadow matching the button's shape).
- **`PillToggle<T>`** — an iOS-style segmented toggle: one "sliding" pill under the labels (`AnimatedAlign`), generic over the value type — used for both the goal period and the appearance theme.
- **`SegChip`** — a checkless pill chip, for chart/tag toggles in Statistics.
- **`ErrorView`** / **`NotebookEmptyState`** — see section 6.
- **`FancyDialogCard` / `showFancyDialog` / `showFancyRawDialog`** — the unified dialog "engine": a spring scale+fade over a 45%-alpha scrim, a 64px medallion icon (14%-alpha colored circle + icon) that pops in with a delay after the dialog itself.
- **`showFancyToast`** (`ToastTone.success/info/error`) — a bottom-screen toast replacing `SnackBar`: a card with a colored stripe on the left (4px), an icon and text (max 3 lines), slides in with a spring, dismisses on tap or timeout (3200 ms by default).
- **`showAchievementPopup`** — a celebratory banner at the top of the screen: an emoji medallion with a "pop" effect (TweenSequence 0.3→1.18→1.0), 7 sparks that scatter and fade, a pulsing warm background glow, swipe up to dismiss, shows multiple achievements one after another (via `Future`, not stacked all at once).
- **`StaggerReveal`** — cascading reveal of list items; the `active` parameter prevents the animation from playing while the widget is built off-screen (e.g. an adjacent `TabBarView` tab).
- **`SubtaskChecklist`** — a collapsible (`AnimatedSize`) subtask checklist with a tappable "2/3" ring indicator that marks everything at once.
- **`StarRating`** — a quality rating (shown in a dialog when completing a task/goal), embedded in `FancyDialogCard`.
- **`PomodoroBanner`** — the active Pomodoro timer banner (25 min focus / 5 min break) above the rings on the Today screen; hidden until the timer is started. State lives in a provider, so switching tabs doesn't reset the countdown. A completed focus session is automatically logged as actual time spent on the task (feeds the estimate-accuracy analytics).
- **`TransferPromptBanner`** (`showTransferPromptBanner`) — a top banner asking "transfer?" for unfinished tasks/goals from a past day/period: the same visual language as `showAchievementPopup` (slides down, spring), but with two actions (yes/no) rather than being purely informational.
- **`TransferCatchupSheet`** — a "catch-up" checklist dialog (built on `FancyDialogCard`), shown if the user didn't open the app at the moment a transfer should have happened — lets them pick what to transfer from the missed candidates.
- **`DeltaIndicator`** — a ▲/▼ triangle + number: the productivity delta vs. last week (green/red/neutral at zero), used on the profile screen.
- **`YearHeatmap`** — a GitHub-style year heatmap (weeks as columns, days as rows), cell color driven by the same composite score `P×(0.7+0.3·T)` used for "best period" in Statistics; on the Profile screen.
- **`TagMini`** — a small tag pill ("#labels"), shared styling for tags on both tasks and goals.
- **`BatteryHintCard`** — a hint card to "allow background activity" (relevant on aggressively background-killing firmware like Transsion/Infinix), shown only when actually needed and if notifications are enabled.
- **`EscDismissible`** — a wrapper that closes a dialog/sheet on `Esc` on desktop (no-op on mobile).

---

## 8. Screens

12 screens, both themes (light/dark), a shared spacing and hierarchy grammar:

1. **Today** (`today_screen.dart`) — the main screen: a built-in month calendar with color-coded day markers (green — everything done, yellow — partial, red — nothing done in the past/today, **blue** — nothing done but the day is still in the future, to avoid inducing anxiety), a journal-style day header (weekday in caps with "Clay", a rule line, a "Templates" button), the day's quote with a drop cap, a double ring (productivity + on-time rate), a time budget for the day, three animated task sections (Needs Attention / Unfinished / Completed, the last one collapsible). `PomodoroBanner` (active focus timer) and `BatteryHintCard` (background hint) may appear at the top; `TransferCatchupSheet` appears on a missed transfer.
2. **Goals** (`goals_screen.dart`) — 4 periods (Week/Month/Season/Year) via `PillToggle`, the same animated section structure as tasks.
3. **Statistics** (`stats_screen.dart`) — productivity charts, best periods, streaks, a task duration estimate-accuracy card (`estimate_accuracy.dart`) and a goal deadline-compliance card (`goal_deadline_accuracy.dart`).
4. **Tag statistics** (`tag_stats_screen.dart`).
5. **Achievements** (`achievements_screen.dart`) — an achievement showcase; unlocking triggers `showAchievementPopup`.
6. **Retrospective** (`retrospective_screen.dart`).
7. **Backlog** (`backlog_screen.dart`) — unfinished tasks/goals left over after a transfer.
8. **Profile** (`profile_screen.dart`) — daily streak, `YearHeatmap` (yearly heatmap), `DeltaIndicator` (productivity delta vs. last week), achievements, weekly summary.
9. **Settings** (`settings_screen.dart`) — theme, background, vignette, backup export/import (dialogs/toasts on the new engine).
10. **About** (`about_screen.dart`) — logo, version, accent Source Serif title.
11. **FAQ** (`faq_screen.dart`).
12. Plus modals — **Day templates** (`templates_sheet.dart`), **Global search** (`global_search.dart`) — use the same component language.

Adaptivity: on a wide (desktop) window, content is wrapped in a centered `ConstrainedBox(maxWidth: 720)` — the UI stays a "page" with side margins instead of stretching across the whole screen; on phones this constraint is transparent (no effect).

---

## 9. Dark theme — not an inversion, a separate decision

- The `primary` accent is swapped for `primarySoft` (#93A7F5) — the plain #3B5BDB lost readability on the charcoal background.
- Card shadow barely works on a dark background → compensated with a thin `surfaceDarkMuted` border.
- `Switch` thumb — color is explicitly pinned in every state (`WidgetStateProperty.resolveWith`): in Material 3 the thumb would swap to a pale `primaryContainer` on hover/disabled and get lost against the background — fixed by forcing the color.
- The vignette flips direction: light theme darkens the edges, dark theme brightens the center.

---

## 10. Buttons — types, placement, appearance

### 10.1 Button types in the system

| Type | Used for | Appearance |
|---|---|---|
| **`FloatingActionButton.extended` via `GlowFab`** | "+ Task", "+ Goal" | An extended FAB bottom-right, `primary` fill, white icon+label, a soft colored halo beneath the button (a negative-spread shadow in the same accent color) |
| **`TextButton.icon`** | Bulk actions below a list ("Transfer all" / "Copy" / "Delete all") | No background, 17px icon + label, compact density (`VisualDensity.compact`), 10×6px padding; "Delete all" — `danger`-colored text, the rest — regular `primary`/`onSurface` |
| **`FilledButton`** | Primary action in dialogs and forms ("Save", "Add", "Delete", "OK") | Solid `primary` fill (`danger` for "Delete"), white text, autofocus on the most common/safe button |
| **`TextButton`** | "Cancel" next to `FilledButton` in dialogs | No background, plain text button, always to the left of the primary action |
| **`OutlinedButton.icon`** | "Save this day as a template" in the templates sheet | Outline instead of fill, 18px `add` icon, full width |
| **`IconButton`** | Search (AppBar), period navigation (`‹` `›`), "Transfer forward" on a single task/goal, counter +/− | Icon-only, 24px, in a circular tap zone, no label or background; `primary` color for active actions |
| **`PopupMenuButton`** (`more_vert` icon, "⋮") | Task/goal/template action menu | Opens a dropdown of `ListTile` items with a leading icon and label; dangerous items ("Delete") — `danger` icon and text |
| **`ActionChip`** | "Unfinished tasks (N)" / "Unachieved goals (N)" | A pill with an `inbox_outlined` 16px icon + count, compact density, leads to the backlog screen |
| **`SegChip`** | Chart grouping and period toggles in "Statistics" | A checkless `ChoiceChip` pill: selected → `primary` fill + white text, unselected → `onSurface 18%` outline |
| **`PillToggle`** | Goal period (Week/Month/Season/Year), appearance theme, background style | Not separate buttons — a single toggle: a "sliding" light/dark pill under the labels on a muted track |
| **Custom row-buttons in a dialog** (`_RecurringChoiceRow`, etc.) | Choosing how to delete a recurring task | Full-width `Material`+`InkWell`: an icon in a colored circle on the left, title/subtitle on the right; the dangerous option ("Entire series") — a red icon |

### 10.2 Placement by screen

**Bottom navigation** (always visible except on modal screens) — a `NavigationBar` with 4 tabs left to right: **Tasks** (`check_circle_outline`/`check_circle`) → **Statistics** (`show_chart_outlined`/`show_chart`) → **Goals** (`flag_outlined`/`flag`) → **Profile** (`person_outline`/`person`). The active icon is filled, with a `primary`-colored pill indicator beneath it (`primarySoft` in dark theme).

**Today:**
- AppBar, right: a "Search tasks" icon button (`search`).
- Bottom-right: `GlowFab` "+ Task" (hidden on past days).
- Below the action row (`Wrap`, right-aligned, after the summary cards): **Transfer all** (`east`, only during the night window 0:00–3:59/23:xx) → **Copy** (`copy_all_outlined`) → **Delete all** (`delete_sweep_outlined`, red; hidden on past days).
- **"Unfinished tasks (N)"** chip — above the action row, left-aligned, shown only when the backlog has items.
- Each task tile, right side: on past days — a single "Transfer forward" icon (`east`) or nothing; on current/future days — a "⋮" menu (Pomodoro focus → Actual time → Transfer forward → Edit → Delete).
- Task counter: minus on the left (`remove_circle_outline`), a tappable current-value zone in the middle, plus on the right (`add_circle`, `primary`).
- Bottom of the task form (sheet): a single full-width `FilledButton` — "Add"/"Save".

**Goals:**
- AppBar, right: "Search goals" (`search`).
- Below the AppBar: a 4-period `PillToggle`.
- Bottom-right: `GlowFab` "+ Goal" (hidden in past periods).
- Inside the list, centered: period navigation `‹` / `›` (`chevron_left`/`chevron_right`).
- **"Unachieved goals (N)"** chip — same pattern as the task backlog.
- Action row (right-aligned): **Transfer all** → **Copy** (opens a period-picker dialog) → **Delete all**.
- Goal tile, right side: "Transfer to current period" (`east`) or a "⋮" menu (Edit / Delete).

**Day templates** (modal sheet): at the top — a full-width `OutlinedButton.icon` "Save this day as a template (N)"; each template in the list has a "⋮" menu on the right (Rename / Delete).

**Settings:** appearance/notification toggles — `SwitchListTile` (the whole row is tappable, with a standard `Switch` on the right); morning/evening review time — a custom "pill" button with a `schedule` icon and the current time, opens a time picker; "Export to file" / "Import from file" / "Help" / "About" — plain `ListTile`s with a `chevron_right` arrow on the right.

**Profile:** AppBar right — a "Settings" icon (`settings_outlined`); the "Weekly summary" and "Achievements" cards are fully tappable (`InkWell`), an emoji icon on the left, a `chevron_right` arrow on the right.

**Statistics / Tag statistics:** grouping and period toggles — a row of `SegChip`s; on the tag screen, AppBar right has a `search` icon that switches to `close` when the search field is open.

**FAQ:** a search field in the AppBar with a `search` icon on the left and a `close` clear button on the right (shown only with a non-empty query); each question is an `ExpansionTile` that expands on tap, no separate button.

**Backlog (tasks/goals):** each row has a `TextButton` on the right ("Complete" / "Achieve") followed by a delete icon button (`delete_outline`, red).

**Retrospective:** centered at the top — week navigation `‹` / `›`; the "forward" button is disabled on the current week.

**Achievements / About:** no action buttons — read-only screens.

**All fancy dialogs** (confirmations, value input, period picker, quality rating): a single bottom layout — `TextButton` "Cancel" on the left, primary `FilledButton` on the right (`danger` fill for dangerous actions, autofocus on the safer of the two buttons).

---

## 11. Principles applied systematically

- A single accent (`clay`), not a "rainbow" of default Material semantic colors.
- A warm shadow/surface temperature instead of the cold Material palette — everywhere, not just in isolated spots.
- Animation as a signal, not decoration: a spring overshoot only where something "came alive" (completion, achievement, ring), ordinary transitions use the calm `easeOut`.
- Error/empty-state copy is human and reassuring, not system-generated/alarming.
- Every visual decision is explainable through the "paper journal" metaphor — that's what makes it a system, not a pile of one-off flourishes.

---
