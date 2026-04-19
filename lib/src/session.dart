// [KimiSession] drives the `kimi` CLI over its JSON-RPC wire protocol.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

import 'errors.dart';
import 'events.dart';
import 'types.dart';

/// Wire protocol version this SDK speaks.
const String kKimiProtocolVersion = '1.7';

/// SDK self-identification sent during `initialize`.
const String kKimiSdkName = 'flutter_kimi_sdk';

/// SDK version sent during `initialize`.
const String kKimiSdkVersion = '0.1.0';

/// Lifecycle of a [KimiSession].
enum KimiSessionState {
  /// Not yet spawned.
  created,

  /// Spawned but `initialize` not yet completed.
  starting,

  /// Ready to accept prompts.
  idle,

  /// A turn is in flight.
  active,

  /// Closed or terminally errored.
  closed,
}

/// A single conversation turn.
///
/// Iterate [events] to consume streamed updates; await [result] for the
/// terminal status. The two are driven by the same underlying RPC, so
/// awaiting [result] before draining [events] will not deadlock — events
/// complete before the result resolves.
class KimiTurn {
  KimiTurn._(this._session, this._requestId);

  final KimiSession _session;
  final String _requestId;
  final StreamController<KimiEvent> _events = StreamController<KimiEvent>();
  final Completer<KimiRunResult> _result = Completer<KimiRunResult>();

  /// Stream of events for this turn, ending when the turn finishes.
  Stream<KimiEvent> get events => _events.stream;

  /// Future resolving to the final status of the turn.
  Future<KimiRunResult> get result => _result.future;

  /// Approve or deny an [ApprovalRequestEvent].
  Future<void> approve(String requestId, ApprovalResponse response,
      {String? reason}) {
    return _session._sendApproval(requestId, response, reason: reason);
  }

  /// Interrupt the running turn. The turn will finish with
  /// [KimiTurnStatus.cancelled].
  Future<void> interrupt() => _session._interrupt();

  void _pushEvent(KimiEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  void _complete(KimiRunResult result) {
    if (!_result.isCompleted) _result.complete(result);
    if (!_events.isClosed) _events.close();
  }

  void _completeError(Object error, StackTrace trace) {
    if (!_result.isCompleted) _result.completeError(error, trace);
    if (!_events.isClosed) _events.close();
  }
}

/// A Kimi CLI session.
///
/// Spawn with [KimiSession.start], then call [initialize] once before sending
/// prompts. Always call [close] when done (or use inside a try/finally).
class KimiSession {
  KimiSession._({
    required this.workDir,
    required this.sessionId,
    required this.executable,
    required this.model,
    required this.thinking,
    required this.yoloMode,
    required this.environment,
    required this.protocolVersion,
  });

  /// The working directory passed to the CLI via `--work-dir`.
  final String workDir;

  /// Session ID. When null the CLI will mint one.
  final String? sessionId;

  /// Path / name of the kimi executable.
  final String executable;

  /// Model identifier to use, or null to take the CLI default.
  final String? model;

  /// Whether to request thinking mode.
  final bool thinking;

  /// Whether to auto-approve all tool calls.
  final bool yoloMode;

  /// Extra environment variables to pass to the child process.
  final Map<String, String>? environment;

  /// Wire protocol version announced in `initialize`. Defaults to
  /// [kKimiProtocolVersion]; override if your `kimi` CLI is on an older
  /// protocol (try "1.0", "1.5", etc.).
  final String protocolVersion;

  /// Callback invoked for each line the CLI writes to stderr. Useful for
  /// surfacing authentication / configuration errors during development.
  void Function(String line)? onStderr;

  /// Callback invoked for each wire message sent or received. Useful for
  /// protocol-level debugging. `direction` is either `'send'` or `'recv'`.
  void Function(String direction, String json)? onWire;

  Process? _process;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;
  final _pending = <String, Completer<Object?>>{};
  KimiTurn? _activeTurn;
  int _nextRequestId = 1;
  String _newRequestId() => '${_nextRequestId++}';
  KimiSessionState _state = KimiSessionState.created;
  final StringBuffer _stderrBuffer = StringBuffer();

  /// Current lifecycle state.
  KimiSessionState get state => _state;

  /// Start a session.
  ///
  /// This spawns the CLI but does not send `initialize` — call [initialize]
  /// before the first [prompt].
  static Future<KimiSession> start({
    required String workDir,
    String? sessionId,
    String executable = 'kimi',
    String? model,
    bool thinking = false,
    bool yoloMode = false,
    Map<String, String>? environment,
    String protocolVersion = kKimiProtocolVersion,
    void Function(String line)? onStderr,
    void Function(String direction, String json)? onWire,
  }) async {
    final session = KimiSession._(
      workDir: workDir,
      sessionId: sessionId,
      executable: executable,
      model: model,
      thinking: thinking,
      yoloMode: yoloMode,
      environment: environment,
      protocolVersion: protocolVersion,
    )
      ..onStderr = onStderr
      ..onWire = onWire;
    await session._spawn();
    return session;
  }

  Future<void> _spawn() async {
    _state = KimiSessionState.starting;
    final args = <String>[
      if (sessionId != null) ...['--session', sessionId!],
      '--work-dir',
      workDir,
      '--wire',
      if (model != null) ...['--model', model!],
      thinking ? '--thinking' : '--no-thinking',
      if (yoloMode) '--yolo',
    ];

    final Process proc;
    try {
      proc = await Process.start(
        executable,
        args,
        environment: environment,
        workingDirectory: workDir,
      );
    } on ProcessException catch (e) {
      _state = KimiSessionState.closed;
      throw KimiTransportException(
        'SPAWN_FAILED',
        'Failed to spawn kimi CLI "$executable": ${e.message}',
        details: e,
      );
    }
    _process = proc;

    _stdoutSub = proc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleLine, onError: _handleStreamError);

    _stderrSub = proc.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      _stderrBuffer.writeln(line);
      if (_stderrBuffer.length > 16 * 1024) {
        // Keep the buffer bounded.
        final tail = _stderrBuffer.toString();
        _stderrBuffer
          ..clear()
          ..write(tail.substring(tail.length - 8 * 1024));
      }
      onStderr?.call(line);
    });

    unawaited(proc.exitCode.then(_handleProcessExit));
  }

  /// Perform the initial `initialize` handshake. Safe to await once.
  ///
  /// Throws a [KimiTransportException] (with any buffered stderr) if the CLI
  /// doesn't answer within [timeout] — a common symptom of a missing binary,
  /// missing credentials, or version-mismatched CLI.
  Future<Map<String, Object?>> initialize({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (_state != KimiSessionState.starting) {
      throw KimiSessionException(
        'INVALID_STATE',
        'initialize() may only be called once after start(), current state: $_state',
      );
    }
    final req = _sendRequest('initialize', {
      'protocol_version': protocolVersion,
      'client': {'name': kKimiSdkName, 'version': kKimiSdkVersion},
      'capabilities': {
        'supports_question': true,
        'supports_plan_mode': true,
      },
    });
    final Object? res;
    try {
      res = await req.timeout(timeout);
    } on TimeoutException {
      throw KimiTransportException(
        'INITIALIZE_TIMEOUT',
        'kimi CLI did not respond to initialize within ${timeout.inSeconds}s. '
        'stderr: ${_stderrBuffer.toString().trim()}',
      );
    }
    _state = KimiSessionState.idle;
    if (res is Map<String, Object?>) return res;
    return <String, Object?>{};
  }

  /// Send a prompt. Returns immediately with a [KimiTurn] you can drain.
  ///
  /// Only one turn can be active at a time — attempting to start another
  /// before the first finishes throws a [KimiSessionException].
  KimiTurn prompt(Object userInput) {
    if (_state != KimiSessionState.idle) {
      throw KimiSessionException(
        'INVALID_STATE',
        'prompt() requires state=idle, got $_state',
      );
    }
    final id = _newRequestId();
    final turn = KimiTurn._(this, id);
    _activeTurn = turn;
    _state = KimiSessionState.active;

    _writeMessage({
      'jsonrpc': '2.0',
      'id': id,
      'method': 'prompt',
      'params': {'user_input': userInput},
    });

    // Wire up the response completer for this request.
    final completer = Completer<Object?>();
    _pending[id] = completer;
    completer.future.then((value) {
      final map = value is Map<String, Object?> ? value : <String, Object?>{};
      final status = KimiTurnStatus.parse(map['status'] as String? ?? '');
      final steps = map['steps'];
      turn._complete(
        KimiRunResult(
          status: status,
          steps: steps is int ? steps : null,
          raw: map,
        ),
      );
      if (_state == KimiSessionState.active) _state = KimiSessionState.idle;
      _activeTurn = null;
    }, onError: (Object error, StackTrace trace) {
      turn._completeError(error, trace);
      if (_state == KimiSessionState.active) _state = KimiSessionState.idle;
      _activeTurn = null;
    });

    return turn;
  }

  /// Gracefully shut down the CLI process.
  Future<void> close({Duration timeout = const Duration(seconds: 5)}) async {
    if (_state == KimiSessionState.closed) return;
    _state = KimiSessionState.closed;
    final proc = _process;
    if (proc == null) return;
    try {
      await proc.stdin.close();
    } catch (_) {
      // stdin may already be closed.
    }
    try {
      await proc.exitCode.timeout(timeout);
    } on TimeoutException {
      proc.kill(ProcessSignal.sigterm);
      try {
        await proc.exitCode.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        proc.kill(ProcessSignal.sigkill);
      }
    }
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
  }

  Future<Object?> _sendRequest(String method, Map<String, Object?> params) {
    final id = _newRequestId();
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _writeMessage({
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    });
    return completer.future;
  }

  Future<void> _sendApproval(
    String requestId,
    ApprovalResponse response, {
    String? reason,
  }) async {
    _writeMessage({
      'jsonrpc': '2.0',
      'id': requestId,
      'result': {
        'request_id': requestId,
        'response': response.wireValue,
        if (reason != null) 'reason': reason,
      },
    });
  }

  Future<void> _interrupt() async {
    final turn = _activeTurn;
    if (turn == null) return;
    _writeMessage({
      'jsonrpc': '2.0',
      'method': 'interrupt',
      'params': {'request_id': turn._requestId},
    });
  }

  void _writeMessage(Map<String, Object?> msg) {
    final proc = _process;
    if (proc == null || _state == KimiSessionState.closed) {
      throw KimiTransportException(
        'STDIN_NOT_WRITABLE',
        'Session is closed',
      );
    }
    try {
      final encoded = jsonEncode(msg);
      onWire?.call('send', encoded);
      proc.stdin.writeln(encoded);
    } catch (e) {
      throw KimiTransportException(
        'STDIN_WRITE_FAILED',
        'Failed to write to CLI stdin: $e',
        details: e,
      );
    }
  }

  void _handleLine(String line) {
    if (line.isEmpty) return;
    onWire?.call('recv', line);
    Map<String, Object?> msg;
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('not a JSON object');
      }
      msg = decoded;
    } catch (e) {
      _failAllPending(
        KimiProtocolException(
          'PARSE_FAILED',
          'Could not decode CLI message: $e',
          details: line,
        ),
      );
      return;
    }

    if (msg.containsKey('id') &&
        (msg.containsKey('result') || msg.containsKey('error'))) {
      _handleResponse(msg);
      return;
    }
    final method = msg['method'];
    if (method is String) {
      if (method == 'request' && msg['id'] != null) {
        _handleServerRequest(msg['params']);
      } else {
        _handleNotification(msg['params']);
      }
    }
  }

  void _handleResponse(Map<String, Object?> msg) {
    final id = msg['id'];
    final String? key = switch (id) {
      final String s => s,
      final int i => '$i',
      _ => null,
    };
    if (key == null) return;
    final completer = _pending.remove(key);
    if (completer == null) return;
    final error = msg['error'];
    if (error != null) {
      final errMap =
          error is Map<String, Object?> ? error : <String, Object?>{};
      completer.completeError(
        KimiCliException(
          (errMap['code']?.toString() ?? 'UNKNOWN'),
          errMap['message']?.toString() ?? 'CLI error',
          details: errMap,
        ),
      );
    } else {
      completer.complete(msg['result']);
    }
  }

  void _handleNotification(Object? params) {
    final turn = _activeTurn;
    if (turn == null || params is! Map<String, Object?>) return;
    final type = params['type'];
    final payload = params['payload'];
    final event = _decodeEvent(
      type is String ? type : 'Unknown',
      payload is Map<String, Object?> ? payload : const <String, Object?>{},
    );
    turn._pushEvent(event);
  }

  void _handleServerRequest(Object? params) {
    final turn = _activeTurn;
    if (turn == null || params is! Map<String, Object?>) return;
    final type = params['type'];
    final payload = params['payload'];
    if (type is! String || payload is! Map<String, Object?>) return;
    if (type == 'ApprovalRequest') {
      turn._pushEvent(
        ApprovalRequestEvent(
          id: payload['id']?.toString() ?? '',
          toolCallId: payload['tool_call_id']?.toString() ?? '',
          sender: payload['sender']?.toString() ?? '',
          action: payload['action']?.toString() ?? '',
          description: payload['description']?.toString() ?? '',
          raw: payload,
        ),
      );
    } else {
      turn._pushEvent(UnknownEvent(type: type, raw: payload));
    }
  }

  /// Test-only hook for exercising the event decoder without spawning a real
  /// CLI session.
  @visibleForTesting
  KimiEvent decodeEventForTest(String type, Map<String, Object?> payload) =>
      _decodeEvent(type, payload);

  KimiEvent _decodeEvent(String type, Map<String, Object?> payload) {
    switch (type) {
      case 'TurnBegin':
        return TurnBeginEvent(userInput: payload['user_input'], raw: payload);
      case 'StepBegin':
        final n = payload['n'];
        return StepBeginEvent(n: n is int ? n : 0, raw: payload);
      case 'StepInterrupted':
        return StepInterruptedEvent(raw: payload);
      case 'ContentPart':
        final kindRaw = payload['type']?.toString() ?? '';
        final kind = switch (kindRaw) {
          'text' => ContentKind.text,
          'thinking' => ContentKind.thinking,
          _ => ContentKind.other,
        };
        final text = switch (kind) {
          ContentKind.text => payload['text']?.toString() ?? '',
          ContentKind.thinking =>
            (payload['text'] ?? payload['thinking'])?.toString() ?? '',
          ContentKind.other => payload['text']?.toString() ?? '',
        };
        return ContentPartEvent(
          kind: kind,
          text: text,
          rawType: kindRaw,
          raw: payload,
        );
      case 'ToolCall':
        final fn = payload['function'];
        final fnMap =
            fn is Map<String, Object?> ? fn : const <String, Object?>{};
        return ToolCallEvent(
          id: payload['id']?.toString() ?? '',
          name: fnMap['name']?.toString() ?? '',
          arguments: fnMap['arguments']?.toString(),
          raw: payload,
        );
      case 'ToolCallPart':
        return ToolCallPartEvent(
          argumentsPart: payload['arguments_part']?.toString() ?? '',
          raw: payload,
        );
      case 'ToolResult':
        final ret = payload['return_value'];
        final retMap =
            ret is Map<String, Object?> ? ret : const <String, Object?>{};
        return ToolResultEvent(
          toolCallId: payload['tool_call_id']?.toString() ?? '',
          isError: retMap['is_error'] == true,
          output: retMap['output']?.toString() ?? '',
          message: retMap['message']?.toString() ?? '',
          raw: payload,
        );
      case 'StatusUpdate':
        final usage = payload['usage'];
        final usageMap =
            usage is Map<String, Object?> ? usage : const <String, Object?>{};
        return StatusUpdateEvent(
          inputTokens: _asInt(usageMap['input_tokens']),
          outputTokens: _asInt(usageMap['output_tokens']),
          contextWindow: _asInt(payload['context_window']),
          raw: payload,
        );
      case 'CompactionBegin':
        return CompactionEvent(started: true, raw: payload);
      case 'CompactionEnd':
        return CompactionEvent(started: false, raw: payload);
      case 'SubagentEvent':
        return SubagentEvent(raw: payload);
      default:
        return UnknownEvent(type: type, raw: payload);
    }
  }

  static int? _asInt(Object? v) => v is int ? v : null;

  void _handleStreamError(Object error, StackTrace trace) {
    _failAllPending(
      KimiTransportException(
        'STDOUT_ERROR',
        'Error reading CLI stdout: $error',
        details: error,
      ),
    );
  }

  void _handleProcessExit(int code) {
    if (code != 0 && _pending.isNotEmpty) {
      _failAllPending(
        KimiTransportException(
          'CLI_EXITED',
          'kimi CLI exited with code $code. stderr: ${_stderrBuffer.toString().trim()}',
        ),
      );
    } else {
      _failAllPending(
        KimiTransportException('CLI_EXITED', 'kimi CLI exited with code $code'),
      );
    }
    _state = KimiSessionState.closed;
  }

  void _failAllPending(Object error) {
    final pending = _pending.values.toList();
    _pending.clear();
    for (final c in pending) {
      if (!c.isCompleted) c.completeError(error);
    }
  }
}
