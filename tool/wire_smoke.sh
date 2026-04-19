#!/usr/bin/env bash
# Smoke-test the kimi CLI wire protocol without copy-paste hazards.
#
# Sends a single `initialize` JSON-RPC request and prints everything the CLI
# writes to stdout/stderr. Use this to figure out whether the SDK or your CLI
# setup is at fault when initialize fails.
#
# Usage:
#   tool/wire_smoke.sh                # protocol 1.7 (default)
#   tool/wire_smoke.sh 1.6            # try a different protocol version
#   KIMI=/path/to/kimi tool/wire_smoke.sh
set -euo pipefail

KIMI_BIN="${KIMI:-$(command -v kimi || echo "$HOME/.local/bin/kimi")}"
PROTO="${1:-1.7}"
WORKDIR="$(pwd)"

if [[ ! -x "$KIMI_BIN" ]]; then
  echo "kimi binary not found or not executable at: $KIMI_BIN" >&2
  echo "Set KIMI=/absolute/path/to/kimi and retry." >&2
  exit 1
fi

read -r -d '' REQ <<EOF || true
{"jsonrpc":"2.0","id":"1","method":"initialize","params":{"protocol_version":"$PROTO","client":{"name":"wire-smoke","version":"0.0.0"},"capabilities":{"supports_question":true,"supports_plan_mode":true}}}
EOF

echo "---- binary : $KIMI_BIN"
echo "---- workDir: $WORKDIR"
echo "---- proto  : $PROTO"
echo "---- send   : $REQ"
echo "---- output ----"

OUT="$(mktemp -t kimi_wire_out.XXXXXX)"
ERR="$(mktemp -t kimi_wire_err.XXXXXX)"
trap 'rm -f "$OUT" "$ERR"' EXIT

# Feed the request, then keep stdin open for 2s so the CLI has time to answer.
# Redirect stdout/stderr to files so the kimi "pipe transport" check sees
# regular pipes, not whatever the enclosing harness uses.
{
  printf '%s\n' "$REQ"
  sleep 2
} | "$KIMI_BIN" --work-dir "$WORKDIR" --wire --no-thinking 2>"$ERR" | tee "$OUT" >/dev/null || true

echo "---- stdout ----"
cat "$OUT"
echo "---- stderr ----"
cat "$ERR"
echo "---- end ----"
