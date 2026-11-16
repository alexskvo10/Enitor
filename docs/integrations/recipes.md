# Integration recipes

Step-by-step recipes for connecting Enitor to other tools. Everything here
works on your own device, with no server of ours — there isn't one. The only
exception is section 8: it uses a server that you run yourself. The exact
request formats are in [formats.md](formats.md).

Open the integrations screen with **Settings → Integrations**. The names
below are the ones you'll see on the screen.

## What works on this device

- **Tasker and Automate** (Android): add tasks, read the day's plan.
- **AI assistants** (Windows, Claude Desktop and similar): the assistant
  runs `enitor-cli` on your PC through MCP.
- **enitor-cli** (Windows): add and finish tasks from a console or a
  scheduled task.
- **Webhooks**: Enitor sends events to addresses *you* enter — n8n,
  Home Assistant, a script on your own machine.
- **Calendar files**: import a `.ics` file or a calendar link, export your
  schedule to `.ics`; move in from Todoist, Google Tasks or TickTick.

Nothing leaves the device until you turn it on. Permissions are off by
default, and each webhook address is a separate choice. Your own server
(section 8) is one more thing you turn on yourself.

---

## 1. Tasker (Android)

### Get the key

1. **Settings → Integrations → Tasker and Automate**.
2. Under **Key**, press **Show** and copy the key.
3. Keep it private. Anyone with the key can send commands as long as the
   key is valid. **New key** issues a new one and the old one stops working
   at once.

### Allow it

**Settings → Integrations → Permissions → Tasker and Automate**:

- **Add tasks and events, mark tasks done — without asking**: turn on, so
  Tasker can add tasks.
- **Read the plan for the day**: turn on only if you want Tasker to read
  your plan. The app asks you to confirm.

Commands without the right key are ignored, and commands from Tasker are
refused while the Tasker switch is off.

### Add a task

Make a Tasker task with one **Send Intent** action:

| Field | Value |
|---|---|
| Action | `dev.enitor.app.COMMAND` |
| Package | `dev.enitor.app` |
| Target | Broadcast Receiver |
| Extra | `key:` followed by your key |
| Extra | `command:{"command":"add_task","args":{"title":"%par1"}}` |

`%par1` is the first argument passed to the task. You can put any Tasker
variable there, for example `%TITLE`, as long as it sits between the quotes.

The same example is on the Tasker screen under **Copy the example**.

### Read the day's plan, with a reply

This needs **Read the plan for the day** in Permissions.

1. Make a Tasker task with **Send Intent**:

   | Field | Value |
   |---|---|
   | Action | `dev.enitor.app.COMMAND` |
   | Package | `dev.enitor.app` |
   | Target | Broadcast Receiver |
   | Extra | `key:` followed by your key |
   | Extra | `command:{"command":"list_today"}` |
   | Extra | `reply_package:net.dinglisch.android.taskerm` |

2. Make a Tasker **profile**: **Event → Intent → Intent Received**, with
   Action `dev.enitor.app.REPLY`. Link it to a task that reads **%reply**.
   The reply is a JSON string with `result.tasks` and `result.schedule`.
   Parse it with a JavaScriptlet action, or show `%reply` in a notification
   while you check the format.

Replies go only to the package named in `reply_package`, and only if that
package is on the list **Apps that may get replies** under Tasker and
Automate. Tasker is on that list by default.

Automate works the same way with package `com.llamalab.automate`.

Every command leaves a quiet note in the notification shade. Turn this off
with **Notify about every command** if you don't want it.

---

## 2. Claude Desktop on Windows (MCP)

The assistant starts `enitor-cli` itself and sees only what your Permissions
allow.

### Copy the setting

1. **Settings → Integrations → AI assistants**.
2. Under **Settings for Claude Desktop (claude_desktop_config.json)**, press
   **Copy the settings**.

The text is a small JSON block. The `command` line is the full path to
`enitor-cli.exe` next to `enitor.exe`. If you move the Enitor folder, copy
the settings again.

### Paste it into the config

1. Press **Win + R**, type `%APPDATA%\Claude`, and press Enter.
2. Open `claude_desktop_config.json` in that folder. If it doesn't exist,
   create it.
3. If the file already has a `"mcpServers"` section, paste only the
   `"enitor"` entry into it. Don't add a second `"mcpServers"` key, or the
   file won't load. The easy case is an empty file, where you paste the whole
   block.
4. Save the file.
5. Quit Claude Desktop fully (right-click its tray icon and quit), then
   start it again.

### Allow it

**Settings → Integrations → Permissions → AI assistants**:

- **Add** — the assistant can add tasks and mark them done.
- **Read the plan for the day** — the assistant can read your plan.

> **Warning about reading.** When "Read" is on, task titles, times and tags
> go to the assistant's model, which runs on the assistant provider's
> servers, not on your device. Enitor itself sends nothing anywhere. Keep
> "Read" off unless you're fine with that.

To check what the assistant has done, look at **Recent calls** on the same
screen. It has a **Clear** button.

---

## 3. n8n

n8n is a workflow tool you can run yourself, or use as a cloud service.
The recipe below runs a workflow that receives Enitor events and checks
their signature.

### Create the webhook

1. In n8n, add a **Webhook** node. Set **HTTP Method** to `POST` and a
   **Path**, for example `enitor`.
2. Open **Options** and turn on **Raw Body**. The signature covers the exact
   bytes Enitor sent, so n8n must not re-encode the body.
3. Copy the **Production URL** of the node.

### Add the address in Enitor

1. **Settings → Integrations → Webhooks → Add an address**.
2. Paste the URL and choose the events (for example **A task is done**).
3. Save, then copy the **Signing secret** from the same screen.
4. Press **Test** to send a `ping`. Check that n8n got it.

### Check the signature

After the Webhook node, add a **Code** node in JavaScript mode. Paste the
secret in place of the placeholder. The code:

```javascript
const crypto = require('crypto');

const SECRET = 'paste the signing secret here';
const MAX_AGE_SECONDS = 5 * 60;

const { headers } = $input.first().json;

// With Raw Body on, the Webhook node puts the exact body bytes into the
// binary property `data`. The signature is over those bytes, not parsed JSON.
const buffer = await this.helpers.getBinaryDataBuffer(0, 'data');
const rawBody = buffer.toString('utf8');

const timestamp = headers['x-enitor-timestamp'];
const signature = headers['x-enitor-signature'] || '';

const age = Math.abs(Date.now() / 1000 - Number(timestamp));
const fresh = Boolean(timestamp) && Number.isFinite(age) && age <= MAX_AGE_SECONDS;

const expected =
  'sha256=' +
  crypto.createHmac('sha256', SECRET).update(`${timestamp}.${rawBody}`).digest('hex');

const a = Buffer.from(signature);
const b = Buffer.from(expected);
const sameLength = a.length === b.length;
const signatureOk = sameLength && crypto.timingSafeEqual(a, b);

if (!fresh || !signatureOk) {
  return [{ json: { ok: false } }];
}

return [{ json: { ok: true, event: JSON.parse(rawBody) } }];
```

Then add an **IF** node on `{{ $json.ok }}`. On the true branch, continue
with your workflow. On the false branch, add a **Respond to Webhook** node
with status `401`. This matters: Enitor retries any answer that isn't `2xx`,
so a forged request should get a clear refusal, not a `500`.

Two things to know:

- Don't re-serialize the body with `JSON.stringify` before checking. The
  bytes must match exactly what was signed.
- Enitor retries a delivery that gets no `2xx` after 1 min, 5 min, 30 min,
  2 h and 12 h. Make the workflow answer fast.

By default n8n doesn't let the Code node load modules, and
`require('crypto')` fails. Allow just that one with the environment variable
`NODE_FUNCTION_ALLOW_BUILTIN=crypto` (with Task Runners — on the runner, not
the main process) and restart n8n. If you can't change the environment,
compute the HMAC with the **Crypto** node over the binary property `data` and
compare in an IF node; that comparison is not constant time, so keep the
Enitor address private.

---

## 4. Home Assistant

Home Assistant can receive a webhook and run an automation from it. It
does **not** check Enitor's signature. Protection comes from keeping the
address on your home network.

### Create the automation

1. **Settings → Automations & scenes → Create automation → Create new
   automation → Edit in YAML**.
2. Paste this, then replace the webhook id and the notification service:

```yaml
alias: Enitor — day closed
description: Tell me when every task of the day is done
triggers:
  - trigger: webhook
    webhook_id: enitor-day-closed-9f3a1c7d
    local_only: true
    allowed_methods:
      - POST
actions:
  - action: notify.mobile_app_your_phone
    data:
      title: Day closed
      message: >-
        {{ trigger.json.data.done }} of {{ trigger.json.data.total }} tasks done,
        productivity {{ trigger.json.data.productivity }}%
mode: single
```

Pick your own long, random `webhook_id`. Replace `notify.mobile_app_your_phone`
with your phone's notification service. Save.

### Point Enitor at it

**Settings → Integrations → Webhooks → Add an address**:

- Address: `http://homeassistant.local:8123/api/webhook/enitor-day-closed-9f3a1c7d`
  (use your Home Assistant's address and the same `webhook_id`).
- Event: **The day is closed**.

Enitor will warn that the address is `http://`. That's expected for a
Home Assistant on your home network, and it's the reason to keep it there.

### Keep it safe

- `local_only: true` makes Home Assistant refuse requests that don't come
  from your local network, including requests that arrive through the cloud
  remote access.
- The `webhook_id` is the only secret in this setup. Treat the address like
  a password: don't post it, and don't put it in a screenshot.

---

## 5. Your own server (any language)

This is the general case: Enitor sends `POST` to an address you run, and
your code checks the signature. Every request has these headers:

- `X-Enitor-Event` — the event type, for example `task.completed`.
- `X-Enitor-Timestamp` — Unix seconds.
- `X-Enitor-Signature` — `sha256=` followed by the hex HMAC-SHA256 of
  `timestamp + "." + body`, with the signing secret as the key.

To check a request: recompute the HMAC over the exact body bytes, compare
with a constant-time function, and reject timestamps older than five
minutes. Enitor sends the same `id` for a repeated fact, so keep the ids you
have processed if a duplicate would cause harm.

A minimal Python receiver:

```python
import hashlib
import hmac
import json
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

SECRET = b"paste the signing secret here"
MAX_AGE_SECONDS = 300


def signature_ok(headers, body: bytes) -> bool:
    timestamp = headers.get("X-Enitor-Timestamp", "")
    signature = headers.get("X-Enitor-Signature", "")
    if not timestamp.isdigit() or abs(time.time() - int(timestamp)) > MAX_AGE_SECONDS:
        return False
    expected = "sha256=" + hmac.new(
        SECRET, timestamp.encode() + b"." + body, hashlib.sha256
    ).hexdigest()
    return hmac.compare_digest(signature, expected)


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)
        if not signature_ok(self.headers, body):
            self.send_response(401)
            self.end_headers()
            return
        event = json.loads(body)
        print(event["type"], event["id"])
        self.send_response(200)
        self.end_headers()


HTTPServer(("127.0.0.1", 8787), Handler).serve_forever()
```

Run it, then add `http://127.0.0.1:8787` as an address in **Webhooks**.
Enitor will show the `http://` warning. A server on the same PC, reached
through `127.0.0.1`, never leaves the machine.

---

## 6. enitor-cli on Windows

`enitor-cli` talks to the running Enitor through a channel that only your
Windows user can open. It's a separate program that comes with the Windows
build.

### Find the path

**Settings → Integrations → Windows → Console: enitor-cli → Copy the path.**
The path is the full location of `enitor-cli.exe`.

### Use it from a console

```text
enitor-cli add Buy milk --date 2026-11-02 --at 18:00 --tag home
enitor-cli today --json
enitor-cli done 3f9a
```

Exit codes: `0` success, `2` wrong arguments, `3` Enitor not running,
`4` forbidden (check Permissions), `5` any other refusal.

To run `enitor-cli` from any folder, add the folder with `enitor-cli.exe`
to your PATH yourself. Enitor doesn't change system settings.

### Run it from Task Scheduler

Use this to add a task every morning.

1. Open **Task Scheduler** → **Create Basic Task**.
2. **Trigger**: Daily, at 08:00.
3. **Action**: Start a program.
4. **Program/script**: the full path you copied, in quotes if it has spaces.
5. **Add arguments**: `add "Check the mail" --tag work`
6. In **Properties** of the task, choose **Run only when user is logged on**.
   The channel opens only to your own user, so the task must run as you.

If Enitor is closed, `enitor-cli` starts it minimised and waits up to 10
seconds. Every run adds a new task, so schedule it once a day, not every
minute.

---

## 7. Calendars and moving in

### Import a timetable (.ics)

Use this for a university timetable or a work rota.

1. **Settings → Integrations → Calendars → Import a calendar
   file (.ics)**.
2. Pick the file. Enitor shows a preview first, including the items it
   can't import (all-day events, "the second Tuesday", yearly rules) and
   why.
3. Import. The items land in the **Schedule** tab.

Importing the same calendar again updates its items instead of duplicating
them.

### Import a calendar by link

1. **Import a calendar by link**, paste the `.ics` link, press **Load**.
2. The calendar is fetched once, when you press the button. **Update once a
   day when Enitor opens** is off by default. If you turn it on, the
   calendar's server sees every request: your address and the time.

An `http://` link gets a warning. Load it only if you trust the network.

### Export to a calendar

**Export to a calendar (.ics)** saves your schedule and timed tasks from the
last 30 days. Google Calendar, Outlook and Apple Calendar can import the file.

### Move in from another app

**Settings → Data → Move in from another app**. Export a file from
the old app first, then pick it here. You see a preview before anything is
imported.

- **Todoist**: in the project, **⋯ → Export as a template (CSV)**.
- **Google Tasks**: on takeout.google.com, choose **Tasks**, then
  **Tasks.json**.
- **TickTick**: **Settings → Account → Generate backup (CSV)**.

---

## 8. Sync phone and PC through your own server

Enitor can sync through a server you run yourself, on your PC or a home
server. This is not section 5, which is about receiving webhooks. The full
guide, with every route and rule, is in [server.md](server.md).

### Start the server

Run `enitor-server` with a folder for the data:

```
enitor_server.exe --data C:\enitor-data
```

The first start prints the token. To see it again, run the same program with
`--show-token`.

### Connect the phone and the PC

On each device open **Settings → Sync → Own server**, press
**Connect server**, and enter the address and the token. The first time,
choose **Merge with the data on the server**.

At home, start the server with `--host 0.0.0.0` and use the PC's address,
for example `http://192.168.1.10:8787`. Outside your home, use an HTTPS
address; the guide shows how to set one up with Caddy.

### Use it from automations

Automations send the same token in the `Authorization` header. Here is how to
add a task for today. `BASE` is the server's address, for example
`http://127.0.0.1:8787` on the PC itself:

```bash
curl -s -X POST "$BASE/v1/tasks" -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"title":"Buy milk"}'
```

The routes and more examples are in [server.md](server.md).

---

## Cloud services

Cloud services such as n8n Cloud or Make can also receive webhooks. You get
their address and enter it in **Webhooks**, the same as your own. Events then
pass through their servers, so choose that with the same care you'd give any
third party. A server you run yourself (section 8) is not a cloud service: it
runs on your own machine.

## What isn't here yet

Enitor doesn't run any server of ours, and nothing in these recipes needs
one. The REST API and the change feed that people ask about are in your own
server, see section 8. Some other things are not built:

- a calendar subscription that Enitor serves,
- a Telegram bot,
- email.

Any of these, if they come later, will come later and only as something you
run yourself, on your own server. We won't host a server for them.
