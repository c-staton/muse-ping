<p align="center">
  <img src="assets/Mark.png" width="88" alt="Ping">
</p>

# Ping

A completion latch for Meta Muse. Mint a wait before dispatching external work. The worker closes it when the wait is done.

It does not wake Muse. There is no public API that drives a user's Muse from outside, so Ping holds the completion until the next scheduled turn picks it up.

## How it works

1. Mint a wait: `POST /v1/waits` with a `source` and a `purpose`.
2. Dispatch the work. Hand the worker the wait id and a push token.
3. The worker posts to `POST /v1/events` when it finishes: `succeeded`, `failed`, or `blocked`.
4. The agent's next turn pulls `GET /v1/inbox` or holds `GET /v1/waits/<id>?timeout=25` and reads the result.

Events are data, not commands. A push token can only ring a doorbell the agent minted. It cannot make the agent do anything.

## What you need

- Python 3. No packages. The server is one stdlib-only file.
- A machine with a public URL if other people should reach your relay.

## Install

```bash
git clone https://github.com/c-staton/muse-ping
cd muse-ping
python3 server/ping.py
```

To run it as a service, see `examples/systemd/ping.service`.

Mint tokens on the machine that runs the server:

```bash
PING_DB=~/.config/ping/ping.db python3 - <<'EOF'
# prints tokens once; store them, they are never shown again
EOF
```

The relay serves its own connector brief at `GET /connectors/muse.md` and an OpenAPI spec at `GET /openapi.json`. Point a Muse custom connector at either one.

## Use

```bash
# mint a wait before dispatching work
curl -s -X POST localhost:17844/v1/waits \
  -d '{"source":"mac","purpose":"TestFlight build 59"}'

# the worker closes it when done
curl -s -X POST localhost:17844/v1/events \
  -H "Authorization: Bearer <push-token>" \
  -H "Idempotency-Key: build-59-done" \
  -d '{"wait_id":"<id>","status":"succeeded","summary":"Build 59 uploaded"}'

# the agent's next turn picks it up
curl -s localhost:17844/v1/inbox -H "Authorization: Bearer <pull-token>"
```

A hook script for workers is in `hooks/ping-hook.sh`. A `ping` CLI wrapper for the agent side is in `skill/`.

## Wake up

Ping is two halves: the latch (this server) and the wake-up (the agent holds a call).

```bash
# hold in a background task — returns the moment ANY wait closes
curl -s 'localhost:17844/v1/wait-any?timeout=25&after=<last_seq>'
```

`agent/wait-any.sh` does this with a cursor file: exit 0 with the event JSON when a completion lands, exit 3 on timeout. Nothing can push-wake an agent from outside. The agent holds this call, and the return is what wakes it. One scheduled task remains the backup.

## Limits, stated plainly

- Ping cannot push-wake an agent. The wake-up is a held long-poll, not a push notification.
- Statuses are fixed: `succeeded`, `failed`, `blocked`. Nothing else.
- Push tokens are stateless bearer tokens. They cannot be revoked individually; delete the row from the tokens table to kill one.
- Self-host it. Do not run one relay for other people's agent completions.

## License

[MIT](LICENSE)
