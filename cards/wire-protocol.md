# Wire Protocol (ACP)

JSON-RPC 2.0 messages exchanged with `kimi acp` over stdin (SDK → CLI) and
stdout (CLI → SDK), following the [Agent Client Protocol](https://agentclientprotocol.com)
version 1. One JSON object per line.

## SDK → CLI (stdin)

| Method | When | Key params |
|--------|------|-----------|
| `initialize` | Once after spawn | `protocolVersion` (int, 1), `clientInfo`, `clientCapabilities` (fs + terminal disabled) |
| `session/new` | After initialize | `cwd`, `mcpServers: []` → returns `sessionId` + `configOptions` |
| `session/load` | Instead of `session/new` when resuming | `sessionId`, `cwd`, `mcpServers` |
| `session/set_config_option` | Apply `model` / `thinking` / `yoloMode` | `sessionId`, `configId` (`model`\|`thinking`\|`mode`), `value` |
| `session/prompt` | Each conversation turn | `sessionId`, `prompt` (content-block list) → responds with `stopReason` |
| `session/cancel` | Interrupt active turn (notification) | `sessionId` |
| Permission response | Reply to `session/request_permission` | `outcome: {outcome: "selected", optionId}` |

## CLI → SDK (stdout)

- **Response** — has `id` + `result` or `error`. Resolves the matching pending `Completer`.
- **`session/update` notification** — `params.update.sessionUpdate` discriminates the payload; decoded into typed `KimiEvent` subclasses (see [event-model](event-model.md)).
- **Server request** — `session/request_permission` (tool approval). Any other agent request (`fs/*`, `terminal/*`) gets a `-32601` error reply — the SDK doesn't advertise those capabilities.

## Config options

`session/new` returns `configOptions`: selects for `model`
(e.g. `kimi-code/kimi-for-coding`), `thinking` (`on`/`off`), and `mode`
(`default`, `plan`, `auto`, `yolo`). Setting an invalid value fails with a
JSON-RPC error surfaced as `KimiCliException`.

## Debugging

Set `onWire` callback on `KimiSession` to log every message with direction
(`"send"` / `"recv"`). Set `onStderr` to capture CLI diagnostic output. Stderr
is also buffered (capped at 16 KB) and included in timeout error messages.
`tool/acp_smoke.dart` runs a real two-turn session (yolo + manual approval);
`SMOKE_VERBOSE=1` prints the wire traffic.
