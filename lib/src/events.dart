// Typed events emitted during a [KimiTurn].

import 'types.dart';

/// Base class for every event on [KimiTurn.events].
sealed class KimiEvent {
  /// Creates a [KimiEvent].
  const KimiEvent({required this.raw});

  /// The raw decoded payload, preserved for forward-compat access.
  final Map<String, Object?> raw;
}

/// Emitted when the CLI accepts the `prompt` call and starts the turn.
class TurnBeginEvent extends KimiEvent {
  /// Creates a [TurnBeginEvent].
  const TurnBeginEvent({required this.userInput, required super.raw});

  /// The user input the turn started from. Either a string or a list of
  /// content-part maps, as returned by the CLI.
  final Object? userInput;
}

/// Emitted when a new step begins within the turn.
class StepBeginEvent extends KimiEvent {
  /// Creates a [StepBeginEvent].
  const StepBeginEvent({required this.n, required super.raw});

  /// Step index (1-based).
  final int n;
}

/// Emitted when a step is interrupted.
class StepInterruptedEvent extends KimiEvent {
  /// Creates a [StepInterruptedEvent].
  const StepInterruptedEvent({required super.raw});
}

/// Text / thinking output streamed from the agent.
class ContentPartEvent extends KimiEvent {
  /// Creates a [ContentPartEvent].
  const ContentPartEvent({
    required this.kind,
    required this.text,
    required this.rawType,
    required super.raw,
  });

  /// Interpreted content kind.
  final ContentKind kind;

  /// The text payload (empty string for non-text kinds).
  final String text;

  /// Original `type` string from the CLI, in case [kind] is [ContentKind.other].
  final String rawType;
}

/// Emitted when the agent invokes a tool.
class ToolCallEvent extends KimiEvent {
  /// Creates a [ToolCallEvent].
  const ToolCallEvent({
    required this.id,
    required this.name,
    required this.arguments,
    required super.raw,
  });

  /// Stable ID for this tool call.
  final String id;

  /// Tool / function name.
  final String name;

  /// Serialized arguments string, if already assembled. May be null during
  /// streaming (see [ToolCallPartEvent]).
  final String? arguments;
}

/// Streaming chunk of tool-call arguments.
class ToolCallPartEvent extends KimiEvent {
  /// Creates a [ToolCallPartEvent].
  const ToolCallPartEvent({required this.argumentsPart, required super.raw});

  /// A chunk of the arguments JSON string.
  final String argumentsPart;
}

/// Emitted when a tool finishes executing.
class ToolResultEvent extends KimiEvent {
  /// Creates a [ToolResultEvent].
  const ToolResultEvent({
    required this.toolCallId,
    required this.isError,
    required this.output,
    required this.message,
    required super.raw,
  });

  /// The tool call this result belongs to.
  final String toolCallId;

  /// Whether the tool reported a failure.
  final bool isError;

  /// String output (for structured output, inspect [raw]).
  final String output;

  /// Human-readable one-line summary from the CLI.
  final String message;
}

/// Emitted with token usage / context info during the turn.
class StatusUpdateEvent extends KimiEvent {
  /// Creates a [StatusUpdateEvent].
  const StatusUpdateEvent({
    required this.inputTokens,
    required this.outputTokens,
    required this.contextWindow,
    required super.raw,
  });

  /// Input tokens consumed so far, or null if not reported.
  final int? inputTokens;

  /// Output tokens produced so far, or null if not reported.
  final int? outputTokens;

  /// Current context-window size if reported.
  final int? contextWindow;
}

/// Context compaction begin / end (no payload).
class CompactionEvent extends KimiEvent {
  /// Creates a [CompactionEvent].
  const CompactionEvent({required this.started, required super.raw});

  /// `true` for CompactionBegin, `false` for CompactionEnd.
  final bool started;
}

/// Emitted when a subagent fires an event.
class SubagentEvent extends KimiEvent {
  /// Creates a [SubagentEvent].
  const SubagentEvent({required super.raw});
}

/// Emitted when the agent needs the user to approve a tool call.
///
/// Respond with [KimiTurn.approve].
class ApprovalRequestEvent extends KimiEvent {
  /// Creates an [ApprovalRequestEvent].
  const ApprovalRequestEvent({
    required this.id,
    required this.toolCallId,
    required this.sender,
    required this.action,
    required this.description,
    required super.raw,
  });

  /// The request ID to pass back to [KimiTurn.approve].
  final String id;

  /// The tool call this approval is for.
  final String toolCallId;

  /// Tool name requesting approval, e.g. `Shell`, `WriteFile`.
  final String sender;

  /// Short action phrase, e.g. `run shell command`.
  final String action;

  /// Detailed human-readable description, e.g. ``Run command `rm -rf /` ``.
  final String description;
}

/// Fallback for any event type the SDK doesn't have a typed class for yet.
class UnknownEvent extends KimiEvent {
  /// Creates an [UnknownEvent].
  const UnknownEvent({required this.type, required super.raw});

  /// Original `type` string as reported by the CLI.
  final String type;
}
