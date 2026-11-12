# Your own Enitor server

Enitor has no server of ours, and this page is not about one. It is about a
server **you** run: `enitor-server`, a small program that ships with Enitor.
It does two things:

- **Sync.** Your phone and your PC each keep a full copy of your data and
  exchange changes through your server, so both end up with the same tasks,
  goals and schedule.
- **REST.** Scripts and automations (Home Assistant, n8n, a shell script)
  read and change your data over plain HTTP, with a token.

The server sits in the middle:

```
phone ──┐
        ├── enitor-server (your PC, NAS or home server) ── REST for automation
PC ─────┘
```

Data goes only to the address you enter in Enitor. Nothing goes to us.

The exact formats of records are in [formats.md](formats.md). The step-by-step
recipes for other tools are in [recipes.md](recipes.md).

---

## Quick start

### 1. Get the server

On Windows it ships with Enitor: `enitor-server.exe` sits next to `enitor.exe`
in the release archive. Anywhere else, build it from the source with the
Flutter SDK:

```
dart build cli -t bin/enitor_server.dart -o build/server
```

On Windows the program is `build/server/bundle/bin/enitor_server.exe`. On Linux
it is the same path without `.exe`. To try it without building, run
`dart run bin/enitor_server.dart` from the project folder.

### 2. Start it

```
enitor_server.exe --data C:\enitor-data
```

By default the server listens on port 8787, only on this computer
(`127.0.0.1`), and keeps data in a folder called `enitor-data`. Give it an
absolute path, so the data does not depend on where you start it from.

| Option | Default | Meaning |
|---|---|---|
| `--port <n>` | 8787 | port to listen on |
| `--host <addr>` | 127.0.0.1 | address to listen on; `0.0.0.0` accepts connections from your home network |
| `--data <dir>` | enitor-data | folder for the data and the token |
| `--token <t>` | — | your own token instead of a generated one; it is written to the token file |
| `--show-token` | — | print the token and exit |
| `-h`, `--help` | — | show the help |

The first start creates a token and prints it once. The token is also kept in
the file `token` inside the data folder. To see it again:

```
enitor_server.exe --data C:\enitor-data --show-token
```

The data folder holds two files: `enitor-data.json` (all your data, as plain
JSON) and `token`. Back up the folder regularly.

### 3. Connect Enitor

On each device open **Settings → Sync → Own server**, press
**Connect server**, and enter:

- the **address**: `http://192.168.1.10:8787` at home, or `https://enitor.example.com`
  outside (see below);
- the **token**.

Then choose one mode:

- **Merge with the data on the server** (the default). Your records go up.
  Where the server already has a record, the server's copy stays.
- **Replace this device's data with the server's data.** The app first saves an
  automatic backup, then empties the local data and downloads the server's.

The server screen shows the last sync time, a **Sync now** button, and a log of
exchanges. To disconnect, press **Disconnect**: the data stays on the device,
and syncing stops.

### 4. At home

Start the server with `--host 0.0.0.0`, allow the port through the firewall if
Windows asks, and use the PC's address in your network, for example
`http://192.168.1.10:8787`. The traffic is plain HTTP, so anyone on your
network can read it. That is fine at home. Do not expose plain HTTP to the
internet.

### 5. Outside the house: HTTPS

Keep the server on `127.0.0.1` and put an HTTPS proxy in front of it. Caddy
gets the certificate by itself. This is a complete `Caddyfile`:

```
enitor.example.com {
	reverse_proxy 127.0.0.1:8787
}
```

The domain must point to your home address, and ports 80 and 443 must reach
the machine running Caddy. Then use `https://enitor.example.com` in Enitor.
Any other HTTPS proxy works the same way: it only has to forward to
`127.0.0.1:8787`.

---

## What is synced

Synced, with the collection names used in the protocol:

- tasks, including their repeat instances and marks (`tasks`);
- goals (`goals`);
- schedule items and series (`schedule`);
- repeat rules (`recurrence`);
- day templates (`templates`);
- the backlogs of tasks and goals (`taskBacklog`, `goalBacklog`);
- day statistics (`dayStats`);
- day and period ratings (`dayRatings`, `periodRatings`).

Not synced: the profile, settings, achievements, and everything kept per device:
the sync settings, the sync log, the push address and the integration keys.
The token is kept in the secure storage of each device.

---

## When it syncs

- When the app starts.
- Three seconds after you change something, so quick edits go in one exchange.
- When you bring the app back to the front.
- While the app is open, the server tells it at once when another device has
  changed something (the event stream, see below). On Windows this works also
  while the window is hidden in the tray.
- Every five minutes, as a fallback.
- When you press **Sync now**.

On Android, in the background, see [Android in the background](#android-in-the-background).

---

## Conflicts

The server numbers every change with a revision. A device sends its changes
together with the revision of the record it last saw (`baseRev`). Two rules
decide the rest:

- **An edit of a known record wins.** If a device edits a record it already
  knew, the edit that arrives later replaces the whole record. There is no
  merge by field. If you edit the same task on two devices before they sync,
  the later edit is kept as a whole.
- **Creating a record that already exists is refused.** If a device creates a
  record the server already has, or has deleted, the server keeps its own
  version and sends it back. This is how two devices creating the same repeat
  instance end up with one task, not two.

## Deletions

A deleted record leaves a mark on the server for 90 days, so other devices
learn about the deletion. When the server starts, marks older than 90 days are
dropped. A device that was offline for longer and then edits a deleted record
brings the record back. This is rare, and nothing is lost.

## Repeats

- A repeating task is one rule (`recurrence`). Each day it applies to is a
  task with the id `r-<rule id>-<yyyymmdd>`, for example
  `r-b2d4e6f8-0000-4000-8000-000000000001-20261028`. The id is the same on every
  device and on the server, so devices never create two copies of one day.
- Until someone marks or edits an instance, it exists only as a virtual entry
  in the day plan, with `"virtual": true`. Marking it creates the real record.
- Deleting one day of a repeating task adds that day to the rule's
  `exceptDates`, so the day does not come back.
- A repeating schedule item is one record with its repeat settings. Changing or
  deleting "only this day" adds the day to the series' `exceptDates`, and a
  change creates a separate one-off item with a new id.

## Restoring a backup

Restoring a backup resets the device's sync state, and the device sends its
records to the server as new. Restoring deletes nothing on the server. A record
the server already has keeps the server's version. A record that is in the
backup but not on the server goes up.

## Android in the background

Android closes the connection when the app goes to the background, so Enitor
wakes up in one of two ways.

1. **UnifiedPush through ntfy (recommended).** Install **ntfy** from F-Droid or
   Google Play. It is a UnifiedPush distributor. When you connect, Enitor
   registers with it automatically, and it registers again on every launch. If
   you install ntfy later, open Enitor once. The server then sends a short
   signal through the distributor whenever there is something new. The signal
   carries only the revision number, no data. If the distributor is a public
   server, the number passes through it, and that is all it learns.
2. **Without ntfy.** Enitor syncs in the background about every 15 minutes, when
   the network is available. Android may delay this to save battery.

Why not Google's push service? It needs Google services and an account.
UnifiedPush does the same job through a distributor you choose.

---

## REST for automation

Every `/v1/` path needs the header `Authorization: Bearer <token>`. Replies are
JSON:

```json
{"ok": true, "result": { ... }}
```

or, on an error, `{"ok": false, "error": {"code": "...", "message": "...", "field": "..."}}`.
See [Errors](#errors).

Dates are `YYYY-MM-DD`, times are `HH:MM` (for example `09:30`). Records use
the same field names as in the export. Day responses use ISO dates, such as
`2026-10-28T00:00:00.000`.

### Routes

| Method | Path | What it does |
|---|---|---|
| GET | `/v1/ping` | check the server and the token; result has `server`, `version`, `rev` |
| GET | `/v1/days/{date}` | one day: `tasks` (with virtual repeat instances), `schedule`, `goals` covering the day, `stats`, `rating` |
| GET | `/v1/days?from=&to=` | several days, at most 62 in one request |
| GET | `/v1/tasks?from=&to=` | stored tasks by date; both parameters are optional; no virtual instances |
| GET | `/v1/tasks/{id}` | one task |
| POST | `/v1/tasks` | create a task |
| PATCH | `/v1/tasks/{id}` | change fields of a task |
| POST | `/v1/tasks/{id}/complete` | mark a task done |
| POST | `/v1/tasks/{id}/uncomplete` | mark it not done |
| DELETE | `/v1/tasks/{id}` | delete a task, or one day of a repeat |
| GET | `/v1/goals?period=&date=` | goals; both parameters are optional |
| GET | `/v1/goals/{id}` | one goal |
| POST | `/v1/goals` | create a goal |
| PATCH | `/v1/goals/{id}` | change fields of a goal |
| POST | `/v1/goals/{id}/progress` | set progress: `{"value": n}` |
| POST | `/v1/goals/{id}/complete` | mark a goal done |
| POST | `/v1/goals/{id}/uncomplete` | mark it not done |
| DELETE | `/v1/goals/{id}` | delete a goal |
| GET | `/v1/schedule` | all schedule items; for one day use `/v1/days/{date}` |
| GET | `/v1/schedule/{id}` | one schedule item |
| POST | `/v1/schedule` | create a schedule item or a series |
| PATCH | `/v1/schedule/{id}` | change an item; with `?scope=day&date=` only one day of a series |
| DELETE | `/v1/schedule/{id}` | delete an item; with `?scope=day&date=` only one day of a series |
| POST | `/v1/sync` | the sync protocol, see below |
| GET | `/v1/devices` | devices that synced: `id`, `name`, `lastSeen` (UTC), `push` |
| DELETE | `/v1/devices/{deviceId}` | remove a device from the list (and its push address); it returns on its next sync |
| PUT | `/v1/devices/{deviceId}/push` | set or clear the push address of a device |
| GET | `/v1/events` | event stream (server-sent events) |

Repeat rules are not created through REST. Create a repeat in the app, and it
reaches the server on the next sync. Or send a `recurrence` record through
`/v1/sync`, see [the protocol](#protocol-for-your-own-server).

### Fields

**Tasks** (`POST` and `PATCH`):

- `title`: required on `POST`. Spaces at the ends are trimmed.
- `date`: `YYYY-MM-DD`. On `POST`, without it the task goes to today. Today
  starts at 4:00, so before 4:00 it is the previous day, the same as in the app.
- `start`, `end`: `HH:MM`.
- `priority`: `none`, `low`, `medium` or `high`.
- `done`: `true` or `false`. Sets or clears the completion time.
- `progress`: a whole number, for counter tasks.
- Any other field is written as it is, with the names from the export, for
  example `description`, `estimatedMinutes`, `targetCount`, `tags`, `subtasks`.

`id`, `createdAt` and `virtual` cannot be changed.

**Goals** (`POST` and `PATCH`):

- `title`: required on `POST`.
- `period`: `week`, `month`, `season` or `year`. Default `month`.
- `date`: any day inside the period. Default today.
- `done`: `true` or `false`.
- `progress`: the total progress. The server stores the part you entered by hand,
  which is the total minus what the linked tasks already count. If `targetCount`
  is set and reached, the goal is completed.
- `targetCount` and other fields are written as they are.

**Schedule items** (`POST`, and `PATCH` for a single day):

- `title`: required.
- `date`: `YYYY-MM-DD`, required on `POST`. For a series, the first day.
- `start`: `HH:MM`, required on `POST`. `end`: `HH:MM`, optional.
- `repeat`: `weekly`, `monthly` or `interval`. Without it the item is one-off.
- `weekdays`: days of the week for `weekly`, from 1 (Monday) to 7 (Sunday).
- `weekInterval`: 1 for every week, 2 for every other week.
- `monthDays`: days of the month for `monthly`.
- `intervalDays`: for `interval`, every N days.
- `until`: `YYYY-MM-DD`, the last day of the series.
- `location`, `note`, `reminderMinutes` and other fields are written as they are.

`end` must be later than `start` (no items past midnight), otherwise the
server answers `400` with `field: "end"`. When you move an item, send both.

### Common actions

The examples are for `bash` (Git Bash, Linux, macOS). They assume two variables:

```bash
BASE=http://127.0.0.1:8787
TOKEN=paste-your-token-here
AUTH="Authorization: Bearer $TOKEN"
```

The examples use English text on purpose. Git Bash on Windows passes non-ASCII
arguments in a form the server rejects (`Body is not UTF-8`). Russian text
works when the body comes from a UTF-8 file, for example:

```bash
cat > task.json <<'EOF'
{"title":"Купить молоко","date":"2026-10-28"}
EOF
curl -s -X POST "$BASE/v1/tasks" -H "$AUTH" \
  -H "Content-Type: application/json" \
  --data-binary @task.json
```

In Windows PowerShell call `curl.exe` (not `curl`, which is an alias there),
and put the body into a file the same way.

Check that the server answers:

```bash
curl -s "$BASE/v1/ping" -H "$AUTH"
```

Get the plan for a day:

```bash
curl -s "$BASE/v1/days/2026-10-28" -H "$AUTH"
```

Add a task for a day, with a time and a priority:

```bash
curl -s -X POST "$BASE/v1/tasks" -H "$AUTH" \
  -H "Content-Type: application/json" \
  -d '{"title":"Buy milk","date":"2026-10-28","start":"10:30","end":"11:00","priority":"high"}'
```

The new task is in `result`, and its id is `result.id`. Use that id in the
following examples. Here `TASK_ID` stands for it:

```bash
curl -s -X POST "$BASE/v1/tasks/TASK_ID/complete" -H "$AUTH"
```

Mark it not done again:

```bash
curl -s -X POST "$BASE/v1/tasks/TASK_ID/uncomplete" -H "$AUTH"
```

Move a task to another day:

```bash
curl -s -X PATCH "$BASE/v1/tasks/TASK_ID" -H "$AUTH" \
  -H "Content-Type: application/json" \
  -d '{"date":"2026-10-29"}'
```

Set progress of a counter task (a task with `targetCount`):

```bash
curl -s -X PATCH "$BASE/v1/tasks/TASK_ID" -H "$AUTH" \
  -H "Content-Type: application/json" \
  -d '{"progress":5}'
```

Delete a task:

```bash
curl -s -X DELETE "$BASE/v1/tasks/TASK_ID" -H "$AUTH"
```

Mark one day of a repeat done. The id of an instance is `r-<rule id>-<yyyymmdd>`.
The rule id is in the field `recurrenceRuleId` of the instance in `/v1/days`:

```bash
curl -s -X POST "$BASE/v1/tasks/r-b2d4e6f8-0000-4000-8000-000000000001-20261028/complete" -H "$AUTH"
```

Delete one day of a repeat. The day is skipped from now on:

```bash
curl -s -X DELETE "$BASE/v1/tasks/r-b2d4e6f8-0000-4000-8000-000000000001-20261026" -H "$AUTH"
```

Create a goal for the year, with a target of 12:

```bash
curl -s -X POST "$BASE/v1/goals" -H "$AUTH" \
  -H "Content-Type: application/json" \
  -d '{"title":"Read 12 books","period":"year","targetCount":12}'
```

Set its progress to 5 out of 12:

```bash
curl -s -X POST "$BASE/v1/goals/GOAL_ID/progress" -H "$AUTH" \
  -H "Content-Type: application/json" \
  -d '{"value":5}'
```

Show the goals of the year that covers 28 October:

```bash
curl -s "$BASE/v1/goals?period=year&date=2026-10-28" -H "$AUTH"
```

Add a one-off schedule item:

```bash
curl -s -X POST "$BASE/v1/schedule" -H "$AUTH" \
  -H "Content-Type: application/json" \
  -d '{"title":"Physics class","date":"2026-10-28","start":"09:00","end":"10:30","location":"Room 301"}'
```

Add a series: a class on Monday, Wednesday and Friday until 18 December:

```bash
curl -s -X POST "$BASE/v1/schedule" -H "$AUTH" \
  -H "Content-Type: application/json" \
  -d '{"title":"Physics class","date":"2026-10-26","start":"09:00","end":"10:30","repeat":"weekly","weekdays":[1,3,5],"until":"2026-12-18"}'
```

Delete one day of that series (for example, the class is cancelled on 28 October):

```bash
curl -s -X DELETE "$BASE/v1/schedule/SCHEDULE_ID?scope=day&date=2026-10-28" -H "$AUTH"
```

Move one day of the series to 11:00 to 12:30. This creates a one-off item for
that day and returns it:

```bash
curl -s -X PATCH "$BASE/v1/schedule/SCHEDULE_ID?scope=day&date=2026-10-30" -H "$AUTH" \
  -H "Content-Type: application/json" \
  -d '{"start":"11:00","end":"12:30"}'
```

Get a range of days, for example a week:

```bash
curl -s "$BASE/v1/days?from=2026-10-26&to=2026-11-01" -H "$AUTH"
```

### Errors

Every error has the same shape:

```json
{"ok": false, "error": {"code": "bad_args", "message": "title is required", "field": "title"}}
```

`field` is there when one field is to blame.

| HTTP status | `code` | When |
|---|---|---|
| 400 | `bad_json` | the body is not JSON or not a JSON object |
| 400 | `bad_args` | a value is missing or in the wrong form (a date, a time, a priority, a range) |
| 400 | `bad_record` | the record does not fit the app's format |
| 400 | `bad_request` | `/v1/sync` got no `cursor` or no `changes` |
| 401 | `unauthorized` | the token is missing or wrong |
| 404 | `not_found` | no such record or path |
| 500 | `internal` | something went wrong on the server; the message says what |

An unknown path under `/v1/` gives 404. An `OPTIONS` request gives 204 with the
CORS headers.

---

## Protocol for your own server

Use this part if you write your own server, in any language, instead of
running `enitor-server`. The reference server is the best example of every
rule here. Its code is in `lib/server/` of the Enitor project.

### Ping

`GET /v1/ping` returns `server`, `version` (now 1) and the current `rev`.

### Sync: `POST /v1/sync`

The device sends its changes and asks for the others:

```json
{
  "v": 1,
  "deviceId": "3f0c9a2e-7d41-4b8e-9a0c-6e5f1d2c3b4a",
  "deviceName": "Windows · DESKTOP-1",
  "cursor": 120,
  "changes": [
    {"coll": "tasks", "id": "c447f9d3-7a73-4e3f-83ab-f25134231936", "baseRev": 118,
     "data": {"id": "c447f9d3-7a73-4e3f-83ab-f25134231936", "title": "Buy milk",
              "date": "2026-10-28T00:00:00.000", "createdAt": "2026-10-28T09:00:00.000",
              "updatedAt": "2026-10-28T10:00:00.000"}},
    {"coll": "tasks", "id": "04667cc0-37f0-421f-ae41-62f5410bf955", "baseRev": 97, "deleted": true}
  ]
}
```

- `cursor`: the last revision this device has seen. Use `0` the first time.
- `changes[].coll`: one of `tasks`, `goals`, `schedule`, `recurrence`,
  `templates`, `taskBacklog`, `goalBacklog`, `dayStats`, `dayRatings`,
  `periodRatings`.
- `changes[].id`: the record id. For `dayStats`, `dayRatings` and
  `periodRatings` it is the key of the day or period, for example
  `2026-10-28T00:00:00.000`.
- `changes[].baseRev`: the revision of the record the device last saw, or `0`
  for a new record.
- `changes[].data`: the whole record, in the app's format. A rating is
  `{"value": n}` with `n` from 1 to 10.
- `changes[].deleted`: `true` for a deletion; then there is no `data`.

The reply:

```json
{
  "ok": true,
  "result": {
    "cursor": 124,
    "applied": [
      {"coll": "tasks", "id": "sync-task-1", "rev": 121}
    ],
    "changes": [
      {"coll": "tasks", "id": "04667cc0-37f0-421f-ae41-62f5410bf955", "rev": 122, "data": { ...the whole record... }},
      {"coll": "tasks", "id": "c447f9d3-7a73-4e3f-83ab-f25134231936", "rev": 123, "deleted": true}
    ],
    "errors": [
      {"coll": "nope", "id": "x", "message": "unknown record"}
    ]
  }
}
```

- `cursor`: the server's current revision. Save it for the next request.
- `applied`: the changes the server accepted, with their new revisions.
- `changes`: every record that changed after your `cursor`, except the ones
  you just applied. A record that was refused comes back here as the server's
  version.
- `errors`: changes that were not applied at all, with the reason. An unknown
  collection or a record that does not fit the app's format is an error.

The rules are the same as in the section [Conflicts](#conflicts): an edit of a
known record wins, a creation over an existing or deleted record is refused.
A deletion needs the revision the device knows (`baseRev` above 0). The
reference server writes the whole record each time; it does not merge fields.

A repeat rule goes the same way, in the `recurrence` collection. Here is a rule
for Monday, Wednesday and Friday, from 20 October. Its instances get the ids
`r-<rule id>-<yyyymmdd>`, see [Repeats](#repeats):

```json
{"v": 1, "deviceId": "3f0c9a2e-7d41-4b8e-9a0c-6e5f1d2c3b4a", "cursor": 0, "changes": [
  {"coll": "recurrence", "id": "b2d4e6f8-0000-4000-8000-000000000001", "baseRev": 0,
   "data": {"id": "b2d4e6f8-0000-4000-8000-000000000001", "taskTitle": "Drink water",
            "kind": "weekly", "weekdays": [1, 3, 5], "startDate": "2026-10-20T00:00:00.000",
            "createdAt": "2026-10-20T08:00:00.000", "updatedAt": "2026-10-20T08:00:00.000"}}
]}
```

The device keeps, for every record, a hash and a revision from the last
exchange. That is how it finds its own changes without any marks on the
records. A device that has no such base sends everything as new.

### Event stream: `GET /v1/events`

A long-lived response with `Content-Type: text/event-stream`. The first event
comes at once with the current revision. After that, one event for every
committed change:

```
event: changed
data: {"rev":124}
```

A comment line `: ping` is sent every 25 seconds, so proxies keep the
connection open. A device that sees a revision above its cursor calls
`/v1/sync`. The stream is only a hint: a device that misses it still syncs
every five minutes.

### Push: `PUT /v1/devices/{deviceId}/push`

```bash
curl -s -X PUT "$BASE/v1/devices/3f0c9a2e-7d41-4b8e-9a0c-6e5f1d2c3b4a/push" -H "$AUTH" \
  -H "Content-Type: application/json" \
  -d '{"endpoint":"https://ntfy.example.com/enitor-your-topic?up=1"}'
```

The body is `{"endpoint": "<URL>"}`, or `{"endpoint": null}` to clear it. After
a change the server waits one second, so a burst of changes becomes one signal,
and then sends `POST <endpoint>` with the body `{"rev":124}` to every endpoint.
An endpoint that answers 404 or 410 is forgotten.

---

## Security

- **The token** is the only lock. It is one random secret of 43 characters.
  Keep it private, and do not put it in links or logs. If it leaks, stop the
  server, delete the `token` file in the data folder and start the server
  again: a new token is created. Then reconnect every device with the new token.
- **HTTPS outside your home.** Plain HTTP sends the token and your data in the
  open. Use HTTP only inside your home network.
- **CORS is `*`.** The server sends `Access-Control-Allow-Origin: *`, so a web
  page from any site can call it. That is safe here because the server uses no
  cookies: a page can only use the API with the token, and it has to be given
  the token first.
- **The data is not encrypted on the server.** `enitor-data.json` is plain JSON.
  Anyone who can read the data folder can read your data. Protect the folder
  with the system's permissions, and back it up.
- **The web page at `/`** is a simple interface for one day. It asks for the
  token and keeps it in the browser's local storage. Open it only on devices
  you trust.
- Your server is trusted by you. The server is not checked by Enitor beyond the
  token and the format of the records.

---

## Files

In the data folder:

- `enitor-data.json`: all records, revisions, the deletion marks and the push
  addresses. The server writes it through `enitor-data.json.tmp` and renames
  it, so an interrupted save does not corrupt the file.
- `token`: the token. Created at the first start, or written by `--token`.
