// Errors thrown by the Kimi SDK.

/// Categorises why something went wrong, mirroring the upstream Node SDK.
enum KimiErrorCategory {
  /// Problem moving bytes to/from the CLI process (spawn, stdio, exit).
  transport,

  /// The CLI sent a message that could not be parsed or violated the wire
  /// contract.
  protocol,

  /// The session itself is in the wrong state (already closed, re-initialized,
  /// etc.).
  session,

  /// The CLI reported a failure via a JSON-RPC error response.
  cli,
}

/// Base class for all SDK-thrown exceptions.
class KimiException implements Exception {
  /// Creates a [KimiException].
  KimiException(this.category, this.code, this.message, {this.details});

  /// What kind of failure this is.
  final KimiErrorCategory category;

  /// Short machine-readable code (e.g. `STDIN_NOT_WRITABLE`).
  final String code;

  /// Human-readable description.
  final String message;

  /// Optional structured payload (e.g. JSON-RPC error body).
  final Object? details;

  @override
  String toString() => 'KimiException(${category.name}/$code): $message';
}

/// Transport-layer failure (process spawn, stdio closed, etc.).
class KimiTransportException extends KimiException {
  /// Creates a [KimiTransportException].
  KimiTransportException(String code, String message, {Object? details})
      : super(KimiErrorCategory.transport, code, message, details: details);
}

/// Protocol-layer failure (bad JSON, unknown message type, version mismatch).
class KimiProtocolException extends KimiException {
  /// Creates a [KimiProtocolException].
  KimiProtocolException(String code, String message, {Object? details})
      : super(KimiErrorCategory.protocol, code, message, details: details);
}

/// Session-state failure (e.g. prompt after close).
class KimiSessionException extends KimiException {
  /// Creates a [KimiSessionException].
  KimiSessionException(String code, String message, {Object? details})
      : super(KimiErrorCategory.session, code, message, details: details);
}

/// The CLI returned a JSON-RPC error.
class KimiCliException extends KimiException {
  /// Creates a [KimiCliException].
  KimiCliException(String code, String message, {Object? details})
      : super(KimiErrorCategory.cli, code, message, details: details);
}
