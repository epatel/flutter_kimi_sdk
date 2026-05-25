# Event Model

Sealed class hierarchy rooted at `KimiEvent`. All events carry a `raw` map for forward-compatible field access.

## Event types

| Class | Wire type | Key fields | When emitted |
|-------|-----------|-----------|-------------|
| `TurnBeginEvent` | `TurnBegin` | `userInput` | CLI accepts the prompt |
| `StepBeginEvent` | `StepBegin` | `n` (1-based index) | Agent starts a new reasoning step |
| `StepInterruptedEvent` | `StepInterrupted` | — | Step cancelled mid-flight |
| `ContentPartEvent` | `ContentPart` | `kind`, `text`, `rawType` | Text or thinking output streamed |
| `ToolCallEvent` | `ToolCall` | `id`, `name`, `arguments` | Agent invokes a tool |
| `ToolCallPartEvent` | `ToolCallPart` | `argumentsPart` | Streaming chunk of tool-call arguments |
| `ToolResultEvent` | `ToolResult` | `toolCallId`, `isError`, `output`, `message` | Tool execution completes |
| `StatusUpdateEvent` | `StatusUpdate` | `inputTokens`, `outputTokens`, `contextWindow` | Token usage report |
| `CompactionEvent` | `CompactionBegin` / `CompactionEnd` | `started` (bool) | Context compaction lifecycle |
| `SubagentEvent` | `SubagentEvent` | — (inspect `raw`) | Subagent fires |
| `ApprovalRequestEvent` | `ApprovalRequest` | `id`, `toolCallId`, `sender`, `action`, `description` | Tool needs user approval |
| `UnknownEvent` | anything else | `type` | Forward-compat fallback |

## ContentKind enum

- `text` — regular agent output
- `thinking` — chain-of-thought (requires `thinking: true` on session)
- `other` — anything else (image, audio, future types)

## Consumption pattern

```dart
turn.events.listen((event) {
  switch (event) {
    case ContentPartEvent(:final kind, :final text):
      if (kind == ContentKind.text) stdout.write(text);
    case ToolCallEvent(:final name, :final arguments):
      stderr.writeln('[tool] $name($arguments)');
    case ApprovalRequestEvent():
      // respond via turn.approve(event.id, ...)
    default:
      break;
  }
});
```
