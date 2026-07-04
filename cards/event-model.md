# Event Model

Sealed class hierarchy rooted at `KimiEvent`, decoded from ACP
`session/update` notifications (`KimiSession.decodeSessionUpdate`). All events
carry a `raw` map for forward-compatible field access.

## Event types

| Class | ACP `sessionUpdate` | Key fields | When emitted |
|-------|--------------------|-----------|-------------|
| `TurnBeginEvent` | — (synthetic) | `userInput` | SDK sends `session/prompt` |
| `ContentPartEvent` | `agent_message_chunk`, `agent_thought_chunk`, `user_message_chunk` | `kind`, `text`, `rawType` | Text or thinking output streamed |
| `ToolCallEvent` | `tool_call` | `id`, `name` (title), `kind`, `status`, `arguments` | Agent invokes a tool |
| `ToolCallUpdateEvent` | `tool_call_update` (pending / in_progress) | `toolCallId`, `status`, `text` | Argument or output chunks stream in |
| `ToolResultEvent` | `tool_call_update` (completed / failed) | `toolCallId`, `isError`, `output` | Tool execution finishes |
| `PlanEvent` | `plan` | `entries` | Agent publishes/updates its plan |
| `ApprovalRequestEvent` | — (`session/request_permission` request) | `id`, `toolCallId`, `sender`, `description`, `options` | Tool needs user approval (never in yolo mode) |
| `UnknownEvent` | anything else | `type` | Forward-compat fallback (`available_commands_update`, `current_mode_update`, ...) |

## ContentKind enum

- `text` — regular agent output (`agent_message_chunk`)
- `thinking` — chain-of-thought (`agent_thought_chunk`)
- `other` — anything else (user replay, image, future types)

## Consumption pattern

```dart
turn.events.listen((event) {
  switch (event) {
    case ContentPartEvent(:final kind, :final text):
      if (kind == ContentKind.text) stdout.write(text);
    case ToolCallEvent(:final name, :final kind):
      stderr.writeln('[tool] $name ($kind)');
    case ApprovalRequestEvent(:final id):
      // respond via turn.approve(id, ...)
    default:
      break;
  }
});
```
