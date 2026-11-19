# Enitor integration formats

Format version **1**. Every example in this file is checked by a test: it is
parsed by the same code the app uses, so an example that stops working breaks
the build.

Enitor keeps everything on your device. Nothing here talks to a server of
ours — there is none. Each format below is a way for *your* tools on *your*
device to talk to Enitor, or for Enitor to call an address *you* entered.

## Versions

- Every format carries a version: `v=1` in links, `"v": 1` in JSON.
- Enitor understands the **current and the previous** version of each format.
- Unknown fields are **never dropped silently**: links show them in the
  confirmation form; JSON replies list them in `warnings`.
- A missing version means `1`.
- A version newer than the app understands is refused with
  `unsupported_version` — the app never guesses.

## 1. Links: `enitor://`

Opened from a browser, a note, a QR code, a launcher. A link **never adds
anything by itself**: it opens the usual task (or schedule) form, filled in,
marked “from a link”, and you press Add.

| Action | Parameters |
|---|---|
| `enitor://add` | `title`, `desc`, `date`, `start`, `end`, `priority`, `tags` |
| `enitor://schedule` | `title`, `date`, `start` (required), `end`, `location`, `note` |
| `enitor://open` | `screen` = `today` \| `schedule` \| `goals` \| `settings` \| `integrations` |

Common parameter `v` (version, default `1`).

Value rules:

- Text is UTF-8, percent-encoded (`%20` or `+` for a space). It is decoded
  **once**: `%2520` stays the literal text `%20`.
- `title` — up to 500 characters after trimming. A link without a title
  opens an empty form (the quick-settings tile does exactly this); commands
  (section 2) require it.
- `desc`, `note` — up to 5000 characters; `location` — up to 500. A longer
  value is refused, not cut.
- `date` — `YYYY-MM-DD`, within 5 years of today. Missing — today; before
  04:00 “today” is still yesterday, as everywhere in Enitor.
- `start`, `end` — `HH:MM` (a leading zero may be omitted: `9:05`),
  00:00…23:59. `end` must be later than `start`.
- `priority` — `none` \| `low` \| `medium` \| `high`, case-insensitive.
- `tags` — comma-separated, up to 10 tags of up to 40 characters, `#` is
  stripped.

Examples:

```link
enitor://add?title=Buy%20milk
enitor://add?v=1&title=Call%20mom&date=2026-11-02&start=18:00&end=18:30&priority=high&tags=family
enitor://schedule?title=Physics&date=2026-11-03&start=09:00&end=10:30&location=Room%20214
enitor://open?screen=schedule
enitor://add
```

“Share → Enitor” on Android works the same way: the first line of the shared
text becomes the title, the rest (a link, say) the description, and the form
opens marked “from Share”.

## 2. Commands (Tasker, `enitor-cli`, MCP, the widget)

One model for every keyed input. A request:

```json
{
  "v": 1,
  "command": "add_task",
  "idempotencyKey": "tasker-2026-11-02-milk",
  "args": { "title": "Buy milk", "date": "2026-11-02" }
}
```

- `idempotencyKey` (optional, up to 100 characters): a repeat with the same
  key within 7 days returns the first reply and creates nothing. Without a
  key, every request is a new one.
- Field rules are the same as for links; `title` is required.

### Commands

| Command | `args` | `result` |
|---|---|---|
| `add_task` | `title`, `description`, `date`, `start`, `end`, `priority`, `tags` | `{ "task": Task }` |
| `add_schedule_item` | `title`, `date`, `start` (required), `end`, `location`, `note` | `{ "item": ScheduleItem }` |
| `complete_task` | `id` — full id or a unique prefix of at least 4 characters | `{ "task": Task }` |
| `list_today` | `date` (optional) | `{ "date": "YYYY-MM-DD", "tasks": [Task], "schedule": [ScheduleItem] }` |

More examples:

```json
{ "v": 1, "command": "add_schedule_item", "args": { "title": "Physics", "date": "2026-11-03", "start": "09:00", "end": "10:30", "location": "Room 214" } }
```

```json
{ "v": 1, "command": "complete_task", "args": { "id": "3f9a" } }
```

```json
{ "v": 1, "command": "list_today" }
```

`Task`:
`{ "id", "title", "description"?, "date", "start"?, "end"?, "priority", "tags", "done" }`.
`ScheduleItem`:
`{ "id", "title", "date", "start", "end"?, "location"?, "note"? }` —
`date` is the day it occurs on.

Who may do what is set in Enitor → Settings → Integrations → Permissions:
“Add” (add, mark done) and “Read” (`list_today`) per input. Everything is
off until you turn it on; the widget may mark tasks done but never reads.

### Replies

```reply
{ "v": 1, "ok": true, "result": { "task": { "id": "0b1c2d3e", "title": "Buy milk", "date": "2026-11-02", "priority": "none", "tags": [], "done": false } }, "warnings": [] }
{ "v": 1, "ok": false, "error": { "code": "forbidden", "message": "This is turned off in Enitor → Settings → Integrations → Permissions." }, "warnings": [] }
```

`message` is human text in the app’s language; `field` names the field for
`invalid_args`.

| `code` | Meaning |
|---|---|
| `invalid_args` | A field is missing, too long, or out of range |
| `unknown_command` | No such command |
| `unsupported_version` | `v` is newer than the app understands |
| `forbidden` | This input is not allowed to do this (Permissions) |
| `bad_key` | Tasker: the key is missing or wrong |
| `not_found` | `complete_task`: no task with this id (or the prefix is ambiguous) |
| `internal` | Something went wrong inside the app; nothing was changed |
| `not_ready` | Windows: Enitor is still starting — repeat in a moment |

### Transports

**Android — Tasker, Automate and the like.** An explicit broadcast (Tasker:
*Send Intent*, Target *Broadcast Receiver*):

- Package `dev.enitor.app`, Action `dev.enitor.app.COMMAND`;
- extras: `key` — the key from Integrations → Tasker; `command` — the JSON
  request above as a string; optionally `reply_package` and `request_id`.

Replies are sent only when `reply_package` is on the allowed list in
Integrations (Tasker and Automate by default): a broadcast
`dev.enitor.app.REPLY` **to that package only**, extras `reply` (the JSON
reply) and `request_id`. Nothing is ever broadcast to all apps. Every
command leaves a quiet notification (can be turned off).

**Windows — `enitor-cli` and MCP.** A named pipe
`\\.\pipe\Enitor-<user SID>`, open only to the current user and only
locally. Frame: 4-byte little-endian length + UTF-8 JSON, at most 64 KB; one
reply per request; 5 s timeout. The frame is an envelope:

```pipe
{ "v": 1, "kind": "ping" }
{ "v": 1, "kind": "permissions", "source": "mcp" }
{ "v": 1, "kind": "command", "source": "cli", "request": { "v": 1, "command": "list_today" } }
{ "v": 1, "kind": "link", "url": "enitor://add?title=Milk" }
```

`source` is `cli` or `mcp`; anything else counts as `cli`. `ping` and
`link` reply `{ "ok": true, "result": {} }`; `permissions` replies
`{ "ok": true, "result": { "add": bool, "read": bool } }` — what this input
may do (MCP uses it to list only allowed tools). `enitor-cli` speaks this for
you:

```text
enitor-cli add Buy milk --date 2026-11-02 --at 18:00 --tag home
enitor-cli today --json
enitor-cli done 3f9a
```

Exit codes: 0 success, 2 wrong arguments, 3 Enitor not running, 4 forbidden,
5 any other refusal.

**MCP (AI assistants).** `enitor-cli mcp` is an MCP server over stdio
(JSON-RPC 2.0, protocol versions 2025-06-18, 2025-03-26, 2024-11-05). Tools
are the four commands above with JSON Schema inputs; `list_today` is not
even listed until “Read” is allowed. If Enitor is closed, `enitor-cli`
starts it minimised and waits up to 10 s. Task text is returned as data
(`structuredContent`), never mixed with instructions.

## 3. Webhook events

Enitor sends `POST` to the addresses you added, only for things **you did on
this device**. Undoing an action does not send an “undo” event.

```event
{
  "v": 1,
  "id": "evt_3f9a6c0de1b24a7f9c8d0e1f",
  "type": "task.completed",
  "createdAt": "2026-11-02T18:31:05.120+03:00",
  "data": { "task": { "id": "0b1c2d3e", "title": "Call mom", "date": "2026-11-02", "priority": "high", "tags": ["family"], "done": true } }
}
```

| `type` | `data` |
|---|---|
| `task.completed` | `{ "task": Task }` |
| `day.closed` | `{ "date": "YYYY-MM-DD", "done": int, "total": int, "productivity": 0…100 }` — every task of the day is done |
| `goal.achieved` | `{ "goal": { "id", "title", "period", "target"?, "progress" } }` |
| `ping` | `{}` — sent by the “Test” button |

`id` is a hash of the record id, the type and the format version: a repeat of
the same fact has the same `id`, so receivers can drop duplicates.

Headers:

- `Content-Type: application/json`
- `X-Enitor-Event: task.completed`
- `X-Enitor-Delivery: <random id of this attempt series>`
- `X-Enitor-Timestamp: <unix seconds>`
- `X-Enitor-Signature: sha256=<hex HMAC-SHA256(secret, timestamp + "." + body)>`

To check a delivery: recompute the HMAC over the exact bytes of the body,
compare in constant time, and reject timestamps older than 5 minutes.

Delivery: `2xx` — delivered. `410 Gone` — the address is switched off and you
get a notification. Anything else, a timeout (10 s) or no network — retried
after 1 min, 5 min, 30 min, 2 h, 12 h, then marked “not delivered”. At most
500 deliveries wait in the queue; the log keeps 7 or 30 days.

## 4. Full export

Settings → Integrations → Full export: one JSON file with all your data.

```export
{
  "format": "enitor-export",
  "v": 1,
  "exportedAt": "2026-11-02T18:31:05.120",
  "app": { "version": "0.4.0" },
  "data": { "tasks": [], "goals": [], "schedule": [], "recurrence": [], "templates": [], "scheduleTemplates": [], "taskBacklog": [], "goalBacklog": [], "dayRatings": {}, "periodRatings": {} }
}
```

Each section holds the app’s own records as it stores them (the schemas list
every field): dates are full ISO 8601 local timestamps, `priority` is an index
(0 none … 3 high). `dayRatings` keys are the day’s local midnight
(`2026-11-02T00:00:00.000`), `periodRatings` keys are `w-<monday>` for a week,
`m-YYYY-MM`, `s-YYYY-N` (season) and `y-YYYY`; values are 1…10.

It never contains device-only state (integration settings, webhook queue and
log, widget snapshot), derived numbers (daily statistics — they are
recalculated) or secrets (the Tasker key and webhook secrets live in the
system’s protected storage). JSON Schemas: `docs/integrations/schema/`.

## 5. Calendar files (.ics)

Import: RFC 5545 `VEVENT`s become schedule items. Weekly (also every other
week), monthly by day and daily-every-N rules map directly; `UNTIL`/`COUNT`
set the end, `EXDATE` the skipped days. What Enitor can’t express (all-day
events, “the second Tuesday”, yearly) is skipped with a reason shown before
import. Re-importing the same calendar updates items instead of duplicating
them (the item id is derived from the event `UID`). A calendar link is
fetched once, when you press the button; daily refresh is a separate switch,
off by default.

Export: the schedule, timed repeating tasks and timed tasks from the last 30
days on, with `RRULE`/`EXDATE`, the current time zone as `TZID` +
`VTIMEZONE`, CRLF line ends, lines folded at 75 octets, stable `UID`s.
