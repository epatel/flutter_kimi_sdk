## 0.3.0

- **Breaking: ported from the removed `--wire` protocol to ACP.** Kimi Code CLI
  0.22+ dropped `--work-dir`/`--wire`; the SDK now spawns `kimi acp` and speaks
  the [Agent Client Protocol](https://agentclientprotocol.com) (v1).
- `KimiSession.start`: `thinking` is now `bool?` (null = CLI default);
  `protocolVersion` is now an `int`; `model` takes an ACP config value
  (e.g. `kimi-code/kimi-for-coding`) applied via `session/set_config_option`;
  `sessionId` resumes via `session/load`; new `acpSessionId` getter.
- `yoloMode` sets the session mode to `yolo` and auto-answers any remaining
  permission requests — no `ApprovalRequestEvent` is emitted.
- Events: removed `StepBeginEvent`, `StepInterruptedEvent`, `ToolCallPartEvent`,
  `StatusUpdateEvent`, `CompactionEvent`, `SubagentEvent`; added
  `ToolCallUpdateEvent` and `PlanEvent`; `ApprovalRequestEvent` now carries the
  offered `options` (and lost `action`); `ToolResultEvent.message` merged into
  `output`.
- `KimiRunResult`: `steps` replaced by `stopReason`; `KimiTurnStatus` gains
  `maxTokens` and `refusal`.
- `turn.approve()` selects the ACP permission option matching the
  `ApprovalResponse`; the `reason` parameter is gone (ACP has no equivalent).
- Interrupt is now the `session/cancel` notification.

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
