# Enitor — UI change and improvement log

A full, itemized list of the project's visual/UI changes, in chronological order. Doesn't include purely technical infrastructure with no visual effect (APK signing, offline fonts, data-race fixes) — that's listed separately at the end for completeness.

---

## Final polish before the redesign

1. **Adaptive stats summary block** — on wide screens (≥600px) the three summary cards line up in a single row of equal height (`LayoutBuilder` + `IntrinsicHeight`); on narrow screens — the previous 2+1 layout. Previously, on a laptop you'd get two long cards and one small one underneath.
2. **Color audit** — every "raw" `Colors.green/red/amber/orange/blue/blueGrey/grey` across the app (tasks, goals, statistics, estimate accuracy, profile, retrospective, backlog, templates, search, ratings, subtask checklist, productivity chart) replaced with semantic palette tokens (`success/danger/warning/primary/textSecondary`).
3. **Consistent error states** — a new `ErrorView` component (doodle icon, calm copy, "Retry" button) replaced a bare `Center(Text('Error: $e'))` in six places: today's tasks, daily stats, profile, stats summary, productivity chart, and twice in the backlog.
4. **Max content width on desktop** — on a wide window the app becomes a centered "page" up to 720px with side margins instead of stretching across the whole screen; on phone — no visible effect.
5. **Removed a dead screen** — the unused `calendar_screen.dart` (never wired into the router) was removed along with its folder.
6. **Removed all sign-in/registration UI** — the "Sign in" button, the "Account" tile in settings, the auth screen: decided against cloud sync, so these became dead UI weight.

## "Living Paper" redesign (4 phases)

7. **Phase 1 — shadows and curves.** All cards got a warm two-layer shadow ("stuck onto paper") instead of the standard bluish Material shadow; Material 3's tonal overlay was removed (`surfaceTintColor: transparent`); named motion curves `easeOut` and `spring` (spring overshoot) were added for use across all future animations.
8. **Phase 2 — status "stripes".** Task and goal tiles moved from a solid status-color fill to a thin 4px colored stripe on the left + a subtle background tint (~8%) — status is still legible but doesn't "shout" across the whole tile. Transferred tasks — a separate gray style with no stripe.
9. **Phase 3 — "journal" accents.**
   - Hero progress rings on the main screen: a count-up animation with a spring arc catch-up; fixed a visual "seam" bug on a full ring (an asymmetric gradient changed abruptly at the quarter mark) — replaced with a symmetric `SweepGradient`.
   - Journal-style day header (`_DayMasthead`): weekday in caps with accent "Clay" + a rule line + a "Templates" card.
   - Accent-colored drop cap in the day's quote (Source Serif 4, italic).
   - Living empty state (`NotebookEmptyState`): a ruled notebook background + doodle icon instead of bare "No tasks" text.
10. **Phase 4 — the drawing checkbox.** The stock `Checkbox` was replaced with `DrawCheckBox`: the checkmark isn't drawn instantly but is "traced" along its outline over 340 ms + a splash ring spreads out on completion. Plus a card color-tint cross-fade (260 ms) and a smooth "paper" slide between tabs (Today/Goals/…) over 220 ms.
    - Fix: the checkmark was initially invisible — on tap, the task instantly flew off to "Completed" and the list destroyed the tile before the animation finished. Fixed by making the checkbox respond optimistically right on tap, while the actual model update is delayed by 400 ms so the stroke has time to finish drawing.
    - Fix: the first version of the cross-fade rendered as a gray rectangle in release builds on plain tiles with no tint (`TweenAnimationBuilder` doesn't tolerate `tween.end == null`) — fixed by only using the cross-fade when a tint is actually set.

## Dialogs, toasts, and notifications redesign

11. **Unified dialog "engine"** (`showFancyDialog` / `FancyDialogCard`) — replaced the bare `AlertDialog`/`SimpleDialog` throughout the app: a spring scale+fade entrance, a medallion icon in a colored circle that "pops in" with a slight delay after the dialog itself.
12. **Toasts instead of `SnackBar`** (`showFancyToast`, success/info/error tones) — a card with a colored stripe and icon that slides up from the bottom with a spring. Replaced SnackBar for: backup (export/import), saving/applying a day template, copying tasks and goals.
13. **Achievement popup** (`showAchievementPopup`) — replaced a text `SnackBar`: an emoji medallion with an overshoot "pop" effect, 7 sparks that scatter and fade, a pulsing warm glow, swipe up to dismiss; multiple achievements are shown one after another instead of piled up at once.
14. **Delete-confirmation dialogs** ("Delete all tasks?", "Delete all goals?") — moved to the new engine with an icon and the accent (danger) color.
15. **Recurring-task choice dialog** ("Delete just this one / the whole series") — replaced `SimpleDialog`/`SimpleDialogOption`/`ListTile` with custom row-buttons featuring a circled icon and label; the dangerous option ("Entire series") is visually flagged.
16. **Input dialogs** — setting a counter (task/goal), naming a day template, actual time spent, quality rating (stars) — all moved to the new engine with a medallion icon.
17. **Period-picker dialogs** for copying goals (week/month/season/year) — moved from `AlertDialog` to the new engine; the grid cell palette (today / selected source) switched to the accent "Clay" instead of the default Material `secondaryContainer`/`onSurface` shades.
18. **Backup dialogs in settings** (import confirmation, import result) — moved to the new engine with matching icons (warning / success).

## UX polish and fixing visual bugs in the task list

19. **Removed flicker when switching days on the calendar and when deleting a task.** The root cause was in the data architecture: the day's task list came from a provider that got recreated on every day switch and briefly showed a spinner instead of the list — the whole task block would unmount and then fully replay the cascading reveal animation. The list is now read synchronously from an already-loaded cache, with no intermediate loading state — switching days and deleting a task now look like a single smooth transition, with nothing "disappearing".

---

## Technical infrastructure (no visual effect, listed for completeness)

- Offline fonts — Inter/Manrope/Source Serif 4 are bundled into the app instead of being fetched over the network on first launch (visually identical, but works without internet).
- Android release signing — a dedicated signing key instead of the debug key (required for publishing, no visual effect).
