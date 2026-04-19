## 0.1.0

- Initial release.
- `KimiSession` spawns the `kimi` CLI with `--wire` and speaks protocol v1.7.
- `KimiTurn` streams typed events (`ContentPartEvent`, `ToolCallEvent`,
  `ToolResultEvent`, `ApprovalRequestEvent`, `StatusUpdateEvent`,
  `StepBeginEvent`, `TurnBeginEvent`, `CompactionEvent`, `UnknownEvent`) and
  resolves with a `KimiRunResult`.
- Approval flow: `turn.approve(id, ApprovalResponse.approve)` / `deny`.
- Cancellation: `turn.interrupt()` and `session.close()`.
