# flutter_kimi_sdk

A Dart/Flutter client for the [Kimi Agent SDK](https://github.com/MoonshotAI/kimi-agent-sdk)
by Moonshot AI. This package drives the `kimi` CLI over its JSON-RPC "wire"
protocol (v1.7), so you can embed Kimi Code agent runs inside Dart programs or
Flutter desktop apps — streaming text, handling tool-call approvals, and
running multi-turn conversations.

> Like the official SDKs, this is a **thin wrapper** around the Kimi CLI. You
> must install the `kimi` binary separately and make sure it's on your `PATH`
> (or pass `executable:` explicitly).

## Platform support

| Platform | Status |
|---|---|
| macOS / Linux / Windows (desktop, server, CLI) | Supported |
| Flutter desktop | Supported |
| Flutter iOS / Android / Web | Not supported — these platforms can't spawn child processes. |

## Prerequisites

1. Install the Kimi CLI: <https://github.com/MoonshotAI/kimi-cli>.
2. Authenticate — pick one:
   - Run `kimi login` once (credentials saved to `~/.kimi/config.toml`; reused
     automatically on every subsequent session). **Recommended.**
   - Or export env vars in the shell that launches your app:
     ```bash
     export KIMI_API_KEY=your-api-key
     export KIMI_BASE_URL=https://api.moonshot.ai/v1
     export KIMI_MODEL_NAME=kimi-k2-thinking-turbo
     ```
3. Verify: `kimi --version`.

## Install

```yaml
dependencies:
  flutter_kimi_sdk: ^0.1.0
```

## Quick start

```dart
import 'dart:io';
import 'package:flutter_kimi_sdk/flutter_kimi_sdk.dart';

Future<void> main() async {
  final session = await KimiSession.start(
    workDir: Directory.current.path,
    model: 'kimi-k2-thinking-turbo',
    yoloMode: true, // auto-approve tool calls for demo purposes
  );
  await session.initialize();

  final turn = session.prompt('List the files in this directory and summarise.');
  turn.events.listen((event) {
    if (event is ContentPartEvent && event.kind == ContentKind.text) {
      stdout.write(event.text);
    } else if (event is ToolCallEvent) {
      stderr.writeln('\n[tool] ${event.name}(${event.arguments ?? ''})');
    }
  });

  final result = await turn.result;
  stdout.writeln('\n--\nStatus: ${result.status}, steps: ${result.steps}');
  await session.close();
}
```

## Handling approvals

With `yoloMode: false` the CLI will ask for confirmation before running tools.
Listen for `ApprovalRequestEvent` and respond via `turn.approve`:

```dart
turn.events.listen((event) async {
  if (event is ApprovalRequestEvent) {
    final ok = await askUserIfOk(event.description);
    await turn.approve(
      event.id,
      ok ? ApprovalResponse.approve : ApprovalResponse.reject,
    );
  }
});
```

## Cancellation

```dart
await turn.interrupt();     // ask the agent to stop; result resolves to cancelled
await session.close();       // shut down the CLI process
```

## Event types

| Class | CLI event | Notes |
|---|---|---|
| `TurnBeginEvent` | `TurnBegin` | User input echoed back. |
| `StepBeginEvent` | `StepBegin` | New reasoning step starts. |
| `StepInterruptedEvent` | `StepInterrupted` | Step was cancelled. |
| `ContentPartEvent` | `ContentPart` | `kind` is `text`, `thinking`, or `other`. |
| `ToolCallEvent` | `ToolCall` | Tool invocation started. |
| `ToolCallPartEvent` | `ToolCallPart` | Streaming tool-call arguments chunk. |
| `ToolResultEvent` | `ToolResult` | Tool finished (may be an error). |
| `StatusUpdateEvent` | `StatusUpdate` | Token usage / context info. |
| `CompactionEvent` | `CompactionBegin`/`End` | Context compaction started/finished. |
| `SubagentEvent` | `SubagentEvent` | Nested-agent event. |
| `ApprovalRequestEvent` | (server request) | Tool needs approval. |
| `UnknownEvent` | any other | Forward-compat fallback. |

Every event carries the original decoded JSON via `event.raw` if you need
fields the typed wrapper doesn't expose.

## Example app

See [`example/`](example/) for a minimal Flutter desktop chat UI built on this
package.

## Versioning & compatibility

- Tracks wire protocol **v1.7**.
- Breaking changes to the wire protocol will bump the minor version here.
- Unknown event types and payload fields degrade gracefully via
  `UnknownEvent` and `event.raw`.

## License

Apache 2.0.
