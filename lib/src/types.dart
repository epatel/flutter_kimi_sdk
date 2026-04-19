// Value types exchanged with the Kimi CLI.

/// Response to an [ApprovalRequestEvent].
enum ApprovalResponse {
  /// Allow the tool call to proceed.
  approve,

  /// Approve this and any similar operations for the rest of the session.
  approveForSession,

  /// Reject the tool call.
  reject;

  /// The wire-level string sent back to the CLI.
  String get wireValue => switch (this) {
        ApprovalResponse.approve => 'approve',
        ApprovalResponse.approveForSession => 'approve_for_session',
        ApprovalResponse.reject => 'reject',
      };
}

/// Final status of a [KimiTurn].
enum KimiTurnStatus {
  /// The agent completed normally.
  finished,

  /// The turn was cancelled via [KimiTurn.interrupt] or session close.
  cancelled,

  /// The agent hit the maximum number of steps before finishing.
  maxStepsReached,

  /// The CLI returned a status we don't recognise.
  unknown;

  /// Parses a raw wire value.
  static KimiTurnStatus parse(String raw) => switch (raw) {
        'finished' => KimiTurnStatus.finished,
        'cancelled' => KimiTurnStatus.cancelled,
        'max_steps_reached' => KimiTurnStatus.maxStepsReached,
        _ => KimiTurnStatus.unknown,
      };
}

/// Terminal result of a [KimiTurn].
class KimiRunResult {
  /// Creates a [KimiRunResult].
  const KimiRunResult({required this.status, this.steps, this.raw});

  /// High-level outcome.
  final KimiTurnStatus status;

  /// Number of steps the agent took, if reported.
  final int? steps;

  /// The raw decoded JSON-RPC result, for forward-compat access.
  final Map<String, Object?>? raw;

  @override
  String toString() => 'KimiRunResult(status: $status, steps: $steps)';
}

/// Kind of a [ContentPartEvent].
enum ContentKind {
  /// Regular text output.
  text,

  /// Chain-of-thought / reasoning output (when thinking mode is on).
  thinking,

  /// Anything else the CLI emitted (image, audio, ...).
  other,
}
