# flutter_kimi_sdk

Dart/Flutter client SDK that drives the Kimi Code CLI (`kimi`) over a JSON-RPC wire protocol on stdin/stdout. Provides typed streaming events, tool approval handling, and multi-turn conversation management. Desktop and server only — requires `dart:io` process spawning (no iOS, Android, or web).

## Context cards

### Architecture
- [architecture](cards/architecture.md) — cross-cutting work, onboarding, understanding how components connect

### Domains
- [wire-protocol](cards/wire-protocol.md) — anything touching JSON-RPC messages, message framing, protocol versions, or debugging wire traffic
- [event-model](cards/event-model.md) — adding, modifying, or consuming streamed events from a KimiTurn
- [session-lifecycle](cards/session-lifecycle.md) — session states, startup/shutdown sequence, multi-turn flow, or state transition bugs

### Features
- [tool-approvals](cards/tool-approvals.md) — approval flow, ApprovalRequestEvent handling, yoloMode behavior
