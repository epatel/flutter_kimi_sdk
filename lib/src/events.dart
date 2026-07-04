// Typed events emitted during a [KimiTurn], decoded from ACP session updates.

import 'types.dart';

/// Base class for every event on [KimiTurn.events].
sealed class KimiEvent {
  /// Creates a [KimiEvent].
  const KimiEvent({required this.raw});

  /// The raw decoded payload, preserved for forward-compat access.
  final Map<String, Object?> raw;
}

/// Emitted when the SDK submits the `session/prompt` call that starts the
/// turn. Synthesized locally; ACP has no dedicated turn-begin notification.
class TurnBeginEvent extends KimiEvent {
  /// Creates a [TurnBeginEvent].
  const TurnBeginEvent({required this.userInput, required super.raw});

  /// The user input the turn started from: the ACP content-block list sent
  /// as the prompt.
  final Object? userInput;
}

/// Text / thinking output streamed from the agent
/// (`agent_message_chunk` / `agent_thought_chunk`).
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

  /// Original ACP `sessionUpdate` string, in case [kind] is
  /// [ContentKind.other].
  final String rawType;
}

/// Emitted when the agent invokes a tool (`tool_call`).
class ToolCallEvent extends KimiEvent {
  /// Creates a [ToolCallEvent].
  const ToolCallEvent({
    required this.id,
    required this.name,
    required this.kind,
    required this.status,
    required this.arguments,
    required super.raw,
  });

  /// Stable ID for this tool call.
  final String id;

  /// Tool title, e.g. `Bash`, `WriteFile`.
  final String name;

  /// ACP tool kind, e.g. `execute`, `read`, `edit` — null if not reported.
  final String? kind;

  /// Initial status, usually `pending`.
  final String? status;

  /// Serialized arguments, if the CLI included `rawInput`. Usually null at
  /// this point — arguments stream in via [ToolCallUpdateEvent].
  final String? arguments;
}

/// Streaming progress for a tool call (`tool_call_update` while pending /
/// in progress). Carries argument chunks and intermediate output.
class ToolCallUpdateEvent extends KimiEvent {
  /// Creates a [ToolCallUpdateEvent].
  const ToolCallUpdateEvent({
    required this.toolCallId,
    required this.status,
    required this.text,
    required super.raw,
  });

  /// The tool call this update belongs to.
  final String toolCallId;

  /// Status reported with this update (`pending`, `in_progress`).
  final String? status;

  /// Concatenated text content of this update (argument or output chunks).
  final String text;
}

/// Emitted when a tool finishes executing (`tool_call_update` with status
/// `completed` or `failed`).
class ToolResultEvent extends KimiEvent {
  /// Creates a [ToolResultEvent].
  const ToolResultEvent({
    required this.toolCallId,
    required this.isError,
    required this.output,
    required super.raw,
  });

  /// The tool call this result belongs to.
  final String toolCallId;

  /// Whether the tool reported a failure.
  final bool isError;

  /// Tool output: `rawOutput` when present, otherwise the update's text
  /// content. For structured output, inspect [raw].
  final String output;
}

/// Emitted when the agent publishes or updates its plan (`plan`).
class PlanEvent extends KimiEvent {
  /// Creates a [PlanEvent].
  const PlanEvent({required this.entries, required super.raw});

  /// Plan entries as raw maps (`content`, `priority`, `status`).
  final List<Map<String, Object?>> entries;
}

/// Emitted when the agent needs the user to approve a tool call
/// (ACP `session/request_permission`).
///
/// Respond with [KimiTurn.approve]. Not emitted when `yoloMode` is on —
/// the SDK auto-approves.
class ApprovalRequestEvent extends KimiEvent {
  /// Creates an [ApprovalRequestEvent].
  const ApprovalRequestEvent({
    required this.id,
    required this.toolCallId,
    required this.sender,
    required this.description,
    required this.options,
    required super.raw,
  });

  /// The request ID to pass back to [KimiTurn.approve].
  final String id;

  /// The tool call this approval is for.
  final String toolCallId;

  /// Tool title requesting approval, e.g. `Bash`, `WriteFile`.
  final String sender;

  /// Human-readable description, e.g.
  /// ``Requesting approval to Running: ls -la``.
  final String description;

  /// The options the CLI offered. [KimiTurn.approve] picks by
  /// [ApprovalResponse.optionKind]; inspect these to build a richer UI.
  final List<ApprovalOption> options;
}

/// Fallback for any session update the SDK doesn't have a typed class for
/// (e.g. `available_commands_update`, `current_mode_update`).
class UnknownEvent extends KimiEvent {
  /// Creates an [UnknownEvent].
  const UnknownEvent({required this.type, required super.raw});

  /// Original `sessionUpdate` string as reported by the CLI.
  final String type;
}
