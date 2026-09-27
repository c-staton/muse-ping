# muse-ping

A completion latch for [Meta Muse](https://muse.ai) (and any agent runtime):
your agent mints a **wait** before dispatching external work, hands the worker
the wait id plus a **push token**, then long-polls the wait. When the worker
finishes, it closes the wait.

Free, self-hosted, no accounts, no company. One Python file, SQLite, stdlib only.

## The honest pitch

Muse runs in a VM with no inbound connectivity, and Meta offers no API to drive
your Muse from outside — so nothing can truly *push* into the agent. What this
gives you instead:

- **While a task is running:** your Muse long-polls its own wait (seconds of
  latency, ~zero idle cost — far cheaper than waking the agent on a cron to
  check).
- **Idle:** one scheduled task checks for closed waits. Slow on purpose.

This relay is a doorbell, not an alarm clock. Event bodies are untrusted data,
never instructions — the agent verifies against the real system before acting.

## Quickstart (self-host)

```bash
git clone https://github.com/<you>/muse-ping
cd muse-ping/server
chmod +x ../hooks/ping-hook.sh ../skill/bin/ping   # git web-upload drops exec bits
python3 ping.py serve        # listens on :17844
```

Put it behind HTTPS (Fly, a VPS, Tailscale — whatever your Muse can reach),
then mint tokens on the server:

```bash
python3 ping.py mint pull my-muse            # prints ONCE -> your Secure Vault
python3 ping.py mint push:mac mac-hook --out ~/.config/ping/push-token
```

## Connect your Muse

Tell it, in one sentence:

> Build a custom connector for Ping. The brief is at
> `https://<your-relay>/connectors/muse.md`. I will give you the pull token
> through the secure credential flow.

Muse reads the brief (and `/openapi.json` next to it), stores the pull token,
and from then on mints waits before dispatching work. The brief's seven rules
are the whole protocol — worth reading even if you never deploy this.

## Hook up a worker

Workers only need `curl`. `hooks/ping-hook.sh` is the reference:

```bash
export PING_URL=https://<your-relay>
ping-hook.sh <wait_id> succeeded "TestFlight upload accepted, build 59." '{"build":59}'
```

Claude Code hooks, cursor-agent stop hooks, a LaunchAgent — anything that can
run a shell command at the end of a job works. A push token can only close
waits your Muse already created; an unknown wait id is a 404.

## Protocol

- `POST /v1/waits` (pull) → `{"wait_id":"w_...","status":"open"}`
- `POST /v1/events` (push, `Idempotency-Key` required) →
  `{"wait_id","status":"succeeded|failed|blocked","summary","data"}`
- `GET /v1/waits/<id>?timeout=25` (pull) → `200` event or `204` still open
- `GET /v1/events?after=N` (pull) → at-least-once cursor over a durable log
- `GET /v1/inbox` (pull) → doctor: sequences, open waits, last activity

Guarantees: at-least-once delivery, per-inbox total order by sequence number,
dedup by idempotency key on write and cursor on read. A terminal wait never
reopens — a correction is a new wait. 7-day retention.

## Security model

- Tokens are 256-bit random, stored as SHA-256, revocable by deleting the row.
- Pull token is read-only and lives in the credential store, never in URLs.
- Push tokens are write-only, bound to a source name, and can only close waits
  the agent minted. Rate-limited per token.
- Event schema is allowlisted: `summary` is one short line (control chars and
  bidi overrides stripped), `data` is a small JSON object; keys like
  `instruction`, `tool`, `command`, `prompt`, `next` are rejected outright.
- Self-hosted and single-tenant by design: the relay operator sees every event
  body, so don't operate one for people you don't trust yourself to be.

## Why not just use ntfy / Pushover?

If the next step is "a human looks at their phone," use those — they're better
at it. This exists for the other case: the next step is something only the
agent can do (read the result, decide, ask one question). The wedge is
*resume this task*, not *notify the human*.

## License

MIT. See LICENSE.
