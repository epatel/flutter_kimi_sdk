# flutter_kimi_sdk

A Dart/Flutter client for the [Kimi Code CLI](https://github.com/MoonshotAI/kimi-code)
by Moonshot AI. This package drives `kimi acp` — the CLI's
[Agent Client Protocol](https://agentclientprotocol.com) (ACP) server — so you
can embed Kimi Code agent runs inside Dart programs or Flutter desktop apps:
streaming text, handling tool-call approvals, and running multi-turn
conversations.

> This is a **thin wrapper** around the Kimi CLI. You must install the `kimi`
> binary separately and make sure it's on your `PATH` (or pass `executable:`
> explicitly). Requires a CLI version with the `acp` subcommand (0.22+).

## Platform support

| Platform | Status |
|---|---|
| macOS / Linux / Windows (desktop, server, CLI) | Supported |
| Flutter desktop | Supported |
| Flutter iOS / Android / Web | Not supported — these platforms can't spawn child processes. |

## Prerequisites

1. Install the Kimi Code CLI: <https://github.com/MoonshotAI/kimi-code>.
2. Run `kimi login` once. The CLI stores OAuth tokens and refreshes them
   automatically — no API key to plumb through, no env vars to export.
3. Verify: `kimi --version` (0.22 or later).

## Install

```yaml
dependencies:
  flutter_kimi_sdk: ^0.3.0
```

## Quick start

```dart
import 'dart:io';
import 'package:flutter_kimi_sdk/flutter_kimi_sdk.dart';

Future<void> main() async {
  final session = await KimiSession.start(
    workDir: Directory.current.path,
    yoloMode: true, // auto-approve tool calls for demo purposes
  );
  await session.initialize();

  final turn = session.prompt('List the files in this directory and summarise.');
  turn.events.listen((event) {
    if (event is ContentPartEvent && event.kind == ContentKind.text) {
      stdout.write(event.text);
    } else if (event is ToolCallEvent) {
      stderr.writeln('\n[tool] ${event.name}');
    }
  });

  final result = await turn.result;
  stdout.writeln('\n--\nStatus: ${result.status}');
  await session.close();
}
```

## Models, thinking, and modes

Session configuration goes through ACP config options. The `initialize()`
result lists what's available under `configOptions`; the SDK applies your
choices right after the session is created:

- `model:` — an ACP model value, e.g. `kimi-code/kimi-for-coding`. Leave null
  for the CLI default. Invalid values fail `initialize()` with a
  `KimiCliException`.
- `thinking:` — `true`/`false` to force thinking on/off, or null (default) to
  keep the CLI's setting.
- `yoloMode:` — sets the session mode to `yolo` (auto-approve everything). The
  CLI also offers `default`, `plan`, and `auto` modes; select those yourself
  via the raw config options if you need them.

## Handling approvals

With `yoloMode: false` the CLI asks for confirmation before running tools.
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

`ApprovalResponse.approveForSession` selects the CLI's "approve for this
session" option. The event's `options` list carries everything the CLI
offered, if you want to build a richer UI.

## Cancellation

```dart
await turn.interrupt();     // ACP session/cancel; result resolves to cancelled
await session.close();       // shut down the CLI process
```

## Resuming sessions

`session.acpSessionId` identifies the conversation. Pass it back as
`sessionId:` to a later `KimiSession.start` to resume via ACP `session/load`.

## Event types

| Class | ACP source | Notes |
|---|---|---|
| `TurnBeginEvent` | (synthetic) | Emitted when `session/prompt` is sent. |
| `ContentPartEvent` | `agent_message_chunk` / `agent_thought_chunk` | `kind` is `text`, `thinking`, or `other`. |
| `ToolCallEvent` | `tool_call` | Tool invocation started (`name`, `kind`, `status`). |
| `ToolCallUpdateEvent` | `tool_call_update` (in progress) | Streaming argument/output chunks. |
| `ToolResultEvent` | `tool_call_update` (completed/failed) | Tool finished; `output` from `rawOutput`. |
| `PlanEvent` | `plan` | Agent plan entries. |
| `ApprovalRequestEvent` | `session/request_permission` | Tool needs approval (not in yolo mode). |
| `UnknownEvent` | any other update | Forward-compat fallback. |

Every event carries the original decoded JSON via `event.raw` if you need
fields the typed wrapper doesn't expose.

## Example app

See [`example/`](example/) for a minimal Flutter desktop chat UI built on this
package.

## Versioning & compatibility

- Tracks **ACP protocol v1** as served by Kimi Code CLI 0.22+.
- Versions before 0.3.0 spoke the CLI's legacy `--wire` protocol, which the
  CLI has removed.
- Unknown update types and payload fields degrade gracefully via
  `UnknownEvent` and `event.raw`.

## License

Apache 2.0.
