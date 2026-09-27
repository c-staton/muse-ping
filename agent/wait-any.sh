#!/bin/bash
# wait-any.sh — the wake-up half of Ping.
#
# Holds GET /v1/wait-any until ANY wait closes, then prints the event and
# exits 0. Run it as a background task: the moment it returns, a completion
# landed — wake up and read it with `ping wait <wait_id>` or `ping events`.
#
# Usage: wait-any.sh [timeout]
#   exit 0: a completion landed (event JSON on stdout, cursor advanced)
#   exit 3: timeout, nothing new — hold again
#   exit 1: error
#
# The cursor lives in ~/.config/ping/wait-any.cursor (override with
# PING_CURSOR) so a restarted holder never replays old events.
set -u

PING_URL="${PING_URL:-http://127.0.0.1:17844}"
TOKEN_FILE="${PING_TOKEN_FILE:-$HOME/.config/ping/pull-token}"
CURSOR_FILE="${PING_CURSOR:-$HOME/.config/ping/wait-any.cursor}"
TIMEOUT="${1:-25}"

[ -f "$TOKEN_FILE" ] || { echo "pull token not found: $TOKEN_FILE" >&2; exit 2; }
AFTER=0
[ -f "$CURSOR_FILE" ] && AFTER="$(cat "$CURSOR_FILE" 2>/dev/null || echo 0)"
case "$AFTER" in ''|*[!0-9]*) AFTER=0 ;; esac

TMP="$(mktemp)"
CODE="$(curl -s -m "$((TIMEOUT + 10))" -o "$TMP" -w '%{http_code}' \
  -H "Authorization: Bearer $(cat "$TOKEN_FILE")" \
  "$PING_URL/v1/wait-any?timeout=$TIMEOUT&after=$AFTER")"

if [ "$CODE" = 200 ]; then
  cat "$TMP"; echo
  SEQ="$(python3 -c "import json; print(json.load(open('$TMP'))['seq'])")"
  printf '%s' "$SEQ" > "$CURSOR_FILE"
  rm -f "$TMP"
  exit 0
elif [ "$CODE" = 204 ]; then
  rm -f "$TMP"
  exit 3
else
  echo "wait-any failed: http $CODE" >&2
  rm -f "$TMP"
  exit 1
fi
