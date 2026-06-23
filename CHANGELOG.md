## 0.2.0

- Docs: refresh model examples to current Moonshot ids (`kimi-k2.7-code` et al.);
  the old `kimi-k2-thinking-turbo` example is gone. No code change — `model:` is
  still a free-form passthrough to `kimi --model`.

## 0.1.0

- Initial release.
- `KimiSession` spawns the `kimi` CLI with `--wire` and speaks protocol v1.7.
- `KimiTurn` streams typed events (`ContentPartEvent`, `ToolCallEvent`,
  `ToolResultEvent`, `ApprovalRequestEvent`, `StatusUpdateEvent`,
  `StepBeginEvent`, `TurnBeginEvent`, `CompactionEvent`, `UnknownEvent`) and
  resolves with a `KimiRunResult`.
- Approval flow: `turn.approve(id, ApprovalResponse.approve)` / `deny`.
- Cancellation: `turn.interrupt()` and `session.close()`.
