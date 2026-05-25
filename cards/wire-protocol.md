# Wire Protocol

JSON-RPC 2.0 messages exchanged between the SDK and the `kimi` CLI process over stdin (SDK → CLI) and stdout (CLI → SDK).

## Message types

**SDK → CLI (stdin):**

| Method | When | Key params |
|--------|------|-----------|
| `initialize` | Once after spawn | `protocol_version`, `client.name`, `client.version`, `capabilities` |
| `prompt` | Each conversation turn | `user_input` (string or content-part list) |
| `interrupt` | Cancel active turn | `request_id` |
| Approval response | Reply to `request` | `request_id`, `response` ("approve" / "approve_for_session" / "reject"), optional `reason` |

**CLI → SDK (stdout):**

- **Response** — has `id` + `result` or `error`. Resolves the matching pending `Completer`.
- **Notification** — has `method` but no `id`. Carries `params.type` + `params.payload`, decoded into typed `KimiEvent` subclasses.
- **Server request** — has `method: "request"` + `id`. Currently only `ApprovalRequest` type; SDK must reply with an approval response.

## Capabilities announced

```json
{
  "supports_question": true,
  "supports_plan_mode": true
}
```

## Debugging

Set `onWire` callback on `KimiSession` to log every message with direction (`"send"` / `"recv"`). Set `onStderr` to capture CLI diagnostic output. Stderr is also buffered (capped at 16 KB) and included in timeout error messages.
