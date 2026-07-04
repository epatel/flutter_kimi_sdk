// Value types exchanged with the Kimi CLI over ACP.

/// Response to an [ApprovalRequestEvent].
enum ApprovalResponse {
  /// Allow the tool call to proceed once.
  approve,

  /// Approve this and any similar operations for the rest of the session.
  approveForSession,

  /// Reject the tool call.
  reject;

  /// The ACP permission-option kind this response selects.
  String get optionKind => switch (this) {
        ApprovalResponse.approve => 'allow_once',
        ApprovalResponse.approveForSession => 'allow_always',
        ApprovalResponse.reject => 'reject_once',
      };
}

/// One selectable option on an [ApprovalRequestEvent], as offered by the CLI.
class ApprovalOption {
  /// Creates an [ApprovalOption].
  const ApprovalOption({
    required this.optionId,
    required this.name,
    required this.kind,
  });

  /// Opaque ID sent back to the CLI when this option is selected.
  final String optionId;

  /// Human-readable label, e.g. `Approve once`.
  final String name;

  /// ACP option kind: `allow_once`, `allow_always`, `reject_once`,
  /// or `reject_always`.
  final String kind;
}

/// Final status of a [KimiTurn], derived from the ACP `stopReason`.
enum KimiTurnStatus {
  /// The agent completed normally (`end_turn`).
  finished,

  /// The turn was cancelled via [KimiTurn.interrupt] or session close.
  cancelled,

  /// The agent hit the turn-request limit (`max_turn_requests`).
  maxStepsReached,

  /// The model hit its token limit (`max_tokens`).
  maxTokens,

  /// The model refused to continue (`refusal`).
  refusal,

  /// The CLI returned a stop reason we don't recognise.
  unknown;

  /// Parses a raw ACP `stopReason` value.
  static KimiTurnStatus parse(String raw) => switch (raw) {
        'end_turn' => KimiTurnStatus.finished,
        'cancelled' => KimiTurnStatus.cancelled,
        'max_turn_requests' => KimiTurnStatus.maxStepsReached,
        'max_tokens' => KimiTurnStatus.maxTokens,
        'refusal' => KimiTurnStatus.refusal,
        _ => KimiTurnStatus.unknown,
      };
}

/// Terminal result of a [KimiTurn].
class KimiRunResult {
  /// Creates a [KimiRunResult].
  const KimiRunResult({required this.status, this.stopReason, this.raw});

  /// High-level outcome.
  final KimiTurnStatus status;

  /// The raw ACP `stopReason` string, for values not covered by [status].
  final String? stopReason;

  /// The raw decoded JSON-RPC result, for forward-compat access.
  final Map<String, Object?>? raw;

  @override
  String toString() =>
      'KimiRunResult(status: $status, stopReason: $stopReason)';
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
