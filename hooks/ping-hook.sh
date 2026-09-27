#!/bin/bash
# ping-hook.sh — worker-side hook for the Ping completion latch.
# Usage: ping-hook.sh <wait_id> <succeeded|failed|blocked> <summary> [data-json]
#
# Reads the push token from ~/.config/ping/push-token (mode 0600).
# The wait_id and token are handed to the worker by whoever dispatched the work.
# This script can only CLOSE waits it was told about — it can never open one,
# read the log, or reach any other inbox.
set -u

WAIT_ID="${1:?usage: ping-hook.sh <wait_id> <status> <summary> [data-json]}"
STATUS="${2:?status required}"
SUMMARY="$3"
DATA="${4:-{}}"
PING_URL="${PING_URL:-http://100.101.154.52:17844}"
TOKEN_FILE="${PING_TOKEN_FILE:-$HOME/.config/ping/push-token}"

[ "$STATUS" = succeeded ] || [ "$STATUS" = failed ] || [ "$STATUS" = blocked ] \
    || { echo "status must be succeeded|failed|blocked" >&2; exit 2; }
[ -f "$TOKEN_FILE" ] || { echo "push token not found: $TOKEN_FILE" >&2; exit 2; }

# Build JSON safely with python3 (no jq dependency, no quoting bugs)
PAYLOAD="$(WAIT_ID="$WAIT_ID" STATUS="$STATUS" SUMMARY="$SUMMARY" DATA="$DATA" python3 -c "
import json, os
data = json.loads(os.environ['DATA'])
print(json.dumps({'wait_id': os.environ['WAIT_ID'], 'status': os.environ['STATUS'],
                  'summary': os.environ['SUMMARY'][:240], 'data': data}))
")"

curl -s -m 15 -X POST "$PING_URL/v1/events" \
  -H "Authorization: Bearer $(cat "$TOKEN_FILE")" \
  -H "Idempotency-Key: $(uuidgen 2>/dev/null || python3 -c 'import uuid; print(uuid.uuid4())')" \
  -H 'Content-Type: application/json' \
  -d "$PAYLOAD"
echo
