// [KimiSession] drives the `kimi` CLI as an Agent Client Protocol (ACP)
// server over stdin/stdout (`kimi acp`).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

import 'errors.dart';
import 'events.dart';
import 'types.dart';

/// ACP protocol version this SDK speaks.
const int kKimiAcpProtocolVersion = 1;

/// SDK self-identification sent during `initialize`.
const String kKimiSdkName = 'flutter_kimi_sdk';

/// SDK version sent during `initialize`.
const String kKimiSdkVersion = '0.3.0';

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
  KimiTurn._(this._session);

  final KimiSession _session;
  final StreamController<KimiEvent> _events = StreamController<KimiEvent>();
  final Completer<KimiRunResult> _result = Completer<KimiRunResult>();

  /// Stream of events for this turn, ending when the turn finishes.
  Stream<KimiEvent> get events => _events.stream;

  /// Future resolving to the final status of the turn.
  Future<KimiRunResult> get result => _result.future;

  /// Respond to an [ApprovalRequestEvent].
  ///
  /// [requestId] is [ApprovalRequestEvent.id]. The SDK selects the offered
  /// option whose kind matches [ApprovalResponse.optionKind].
  Future<void> approve(String requestId, ApprovalResponse response) {
    return _session._respondToPermission(requestId, response);
  }

  /// Interrupt the running turn (ACP `session/cancel`). The turn will finish
  /// with [KimiTurnStatus.cancelled].
  Future<void> interrupt() => _session._cancel();

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

class _PermissionRequest {
  _PermissionRequest(this.rpcId, this.options);

  /// The JSON-RPC request id, echoed back verbatim in the response.
  final Object rpcId;
  final List<ApprovalOption> options;
}

/// A Kimi CLI session over ACP.
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

  /// The working directory sent to the CLI as the session `cwd`.
  final String workDir;

  /// Existing ACP session ID to resume via `session/load`. When null a new
  /// session is created and [acpSessionId] holds the CLI-minted ID after
  /// [initialize].
  final String? sessionId;

  /// Path / name of the kimi executable.
  final String executable;

  /// Model config value to select (e.g. `kimi-code/kimi-for-coding`), or null
  /// to take the CLI default. See `configOptions` in the [initialize] result
  /// for the available values.
  final String? model;

  /// Thinking mode: `true` selects `on`, `false` selects `off`, null leaves
  /// the CLI default untouched.
  final bool? thinking;

  /// Whether to auto-approve all tool calls. Sets the session mode to `yolo`
  /// and answers any remaining permission requests with the first
  /// `allow` option, so no [ApprovalRequestEvent] is emitted.
  final bool yoloMode;

  /// Extra environment variables to pass to the child process.
  final Map<String, String>? environment;

  /// ACP protocol version announced in `initialize`. Defaults to
  /// [kKimiAcpProtocolVersion].
  final int protocolVersion;

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
  final _permissionRequests = <String, _PermissionRequest>{};
  KimiTurn? _activeTurn;
  int _nextRequestId = 1;
  String _newRequestId() => '${_nextRequestId++}';
  KimiSessionState _state = KimiSessionState.created;
  final StringBuffer _stderrBuffer = StringBuffer();
  String? _acpSessionId;

  /// Current lifecycle state.
  KimiSessionState get state => _state;

  /// The ACP session ID, available after [initialize]. Pass it as `sessionId`
  /// to a later [KimiSession.start] to resume the conversation.
  String? get acpSessionId => _acpSessionId;

  /// Start a session.
  ///
  /// This spawns `<executable> acp` but does not perform the handshake —
  /// call [initialize] before the first [prompt].
  static Future<KimiSession> start({
    required String workDir,
    String? sessionId,
    String executable = 'kimi',
    String? model,
    bool? thinking,
    bool yoloMode = false,
    Map<String, String>? environment,
    int protocolVersion = kKimiAcpProtocolVersion,
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
    final Process proc;
    try {
      proc = await Process.start(
        executable,
        const ['acp'],
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

  /// Perform the ACP handshake: `initialize`, then `session/new` (or
  /// `session/load` when resuming), then apply the `model` / `thinking` /
  /// `yoloMode` configuration. Safe to await once.
  ///
  /// Returns the `session/new` result, whose `configOptions` list the
  /// available models, thinking levels, and modes.
  ///
  /// Throws a [KimiTransportException] (with any buffered stderr) if the CLI
  /// doesn't answer within [timeout] — a common symptom of a missing binary
  /// or version-mismatched CLI — and a [KimiCliException] if the CLI rejects
  /// a step (e.g. not authenticated: run `kimi login`).
  Future<Map<String, Object?>> initialize({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (_state != KimiSessionState.starting) {
      throw KimiSessionException(
        'INVALID_STATE',
        'initialize() may only be called once after start(), current state: $_state',
      );
    }
    final Object? sessionRes;
    try {
      sessionRes = await _handshake().timeout(timeout);
    } on TimeoutException {
      throw KimiTransportException(
        'INITIALIZE_TIMEOUT',
        'kimi CLI did not respond to initialize within ${timeout.inSeconds}s. '
        'stderr: ${_stderrBuffer.toString().trim()}',
      );
    }
    _state = KimiSessionState.idle;
    if (sessionRes is Map<String, Object?>) return sessionRes;
    return <String, Object?>{};
  }

  Future<Object?> _handshake() async {
    await _sendRequest('initialize', {
      'protocolVersion': protocolVersion,
      'clientInfo': {'name': kKimiSdkName, 'version': kKimiSdkVersion},
      'clientCapabilities': {
        'fs': {'readTextFile': false, 'writeTextFile': false},
        'terminal': false,
      },
    });

    final Object? sessionRes;
    if (sessionId != null) {
      sessionRes = await _sendRequest('session/load', {
        'sessionId': sessionId,
        'cwd': workDir,
        'mcpServers': const <Object>[],
      });
      _acpSessionId = sessionId;
    } else {
      sessionRes = await _sendRequest('session/new', {
        'cwd': workDir,
        'mcpServers': const <Object>[],
      });
      if (sessionRes is Map<String, Object?>) {
        _acpSessionId = sessionRes['sessionId']?.toString();
      }
    }
    if (_acpSessionId == null) {
      throw KimiProtocolException(
        'NO_SESSION_ID',
        'CLI did not return a session ID from session/new',
        details: sessionRes,
      );
    }

    if (model != null) {
      await _setConfigOption('model', model!);
    }
    if (thinking != null) {
      await _setConfigOption('thinking', thinking! ? 'on' : 'off');
    }
    if (yoloMode) {
      await _setConfigOption('mode', 'yolo');
    }
    return sessionRes;
  }

  Future<void> _setConfigOption(String configId, String value) async {
    await _sendRequest('session/set_config_option', {
      'sessionId': _acpSessionId,
      'configId': configId,
      'value': value,
    });
  }

  /// Send a prompt. Returns immediately with a [KimiTurn] you can drain.
  ///
  /// [userInput] is either a plain string (wrapped in a text content block)
  /// or a list of ACP content-block maps (`{'type': 'text', 'text': ...}`).
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
    final blocks = switch (userInput) {
      final String s => [
          {'type': 'text', 'text': s}
        ],
      final List<Object?> l => l,
      final Map<String, Object?> m => [m],
      _ => throw KimiSessionException(
          'INVALID_PROMPT',
          'prompt() takes a String or a list of content-block maps, '
          'got ${userInput.runtimeType}',
        ),
    };

    final turn = KimiTurn._(this);
    _activeTurn = turn;
    _state = KimiSessionState.active;

    final response = _sendRequest('session/prompt', {
      'sessionId': _acpSessionId,
      'prompt': blocks,
    });
    turn._pushEvent(
      TurnBeginEvent(userInput: blocks, raw: const <String, Object?>{}),
    );

    response.then((value) {
      final map = value is Map<String, Object?> ? value : <String, Object?>{};
      final stopReason = map['stopReason']?.toString();
      turn._complete(
        KimiRunResult(
          status: KimiTurnStatus.parse(stopReason ?? ''),
          stopReason: stopReason,
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

  Future<void> _respondToPermission(
    String requestId,
    ApprovalResponse response,
  ) async {
    final req = _permissionRequests.remove(requestId);
    if (req == null) {
      throw KimiSessionException(
        'UNKNOWN_APPROVAL',
        'No pending approval request with id "$requestId"',
      );
    }
    final wantedKind = response.optionKind;
    final option = req.options
        .where((o) => o.kind == wantedKind)
        .firstOrNull ??
        // A rejection should still reject if only reject_always is offered.
        (response == ApprovalResponse.reject
            ? req.options.where((o) => o.kind == 'reject_always').firstOrNull
            : null);
    if (option == null) {
      throw KimiSessionException(
        'NO_MATCHING_OPTION',
        'CLI offered no "$wantedKind" option for approval "$requestId" '
        '(offered: ${req.options.map((o) => o.kind).join(', ')})',
      );
    }
    _writeMessage({
      'jsonrpc': '2.0',
      'id': req.rpcId,
      'result': {
        'outcome': {'outcome': 'selected', 'optionId': option.optionId},
      },
    });
  }

  Future<void> _cancel() async {
    if (_activeTurn == null) return;
    _writeMessage({
      'jsonrpc': '2.0',
      'method': 'session/cancel',
      'params': {'sessionId': _acpSessionId},
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
      final params = msg['params'];
      final paramsMap =
          params is Map<String, Object?> ? params : const <String, Object?>{};
      if (msg.containsKey('id')) {
        _handleAgentRequest(method, msg['id']!, paramsMap);
      } else if (method == 'session/update') {
        _handleSessionUpdate(paramsMap);
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

  void _handleSessionUpdate(Map<String, Object?> params) {
    final turn = _activeTurn;
    if (turn == null) return;
    turn._pushEvent(decodeSessionUpdate(params));
  }

  void _handleAgentRequest(
    String method,
    Object rpcId,
    Map<String, Object?> params,
  ) {
    if (method == 'session/request_permission') {
      _handlePermissionRequest(rpcId, params);
      return;
    }
    // fs/*, terminal/*, and anything else we didn't advertise.
    _writeMessage({
      'jsonrpc': '2.0',
      'id': rpcId,
      'error': {'code': -32601, 'message': 'Method not supported: $method'},
    });
  }

  void _handlePermissionRequest(Object rpcId, Map<String, Object?> params) {
    final options = <ApprovalOption>[
      for (final o in params['options'] as List? ?? const [])
        if (o is Map<String, Object?>)
          ApprovalOption(
            optionId: o['optionId']?.toString() ?? '',
            name: o['name']?.toString() ?? '',
            kind: o['kind']?.toString() ?? '',
          ),
    ];

    if (yoloMode) {
      // Belt and braces on top of mode=yolo: never surface approvals.
      final allow = options.where((o) => o.kind == 'allow_always').firstOrNull ??
          options.where((o) => o.kind == 'allow_once').firstOrNull ??
          options.firstOrNull;
      _writeMessage({
        'jsonrpc': '2.0',
        'id': rpcId,
        'result': {
          'outcome': allow == null
              ? {'outcome': 'cancelled'}
              : {'outcome': 'selected', 'optionId': allow.optionId},
        },
      });
      return;
    }

    final turn = _activeTurn;
    if (turn == null) {
      _writeMessage({
        'jsonrpc': '2.0',
        'id': rpcId,
        'result': {
          'outcome': {'outcome': 'cancelled'},
        },
      });
      return;
    }

    final requestId = 'perm_${_nextRequestId++}';
    _permissionRequests[requestId] = _PermissionRequest(rpcId, options);

    final toolCall = params['toolCall'];
    final toolCallMap =
        toolCall is Map<String, Object?> ? toolCall : const <String, Object?>{};
    turn._pushEvent(
      ApprovalRequestEvent(
        id: requestId,
        toolCallId: toolCallMap['toolCallId']?.toString() ?? '',
        sender: toolCallMap['title']?.toString() ?? '',
        description: _contentText(toolCallMap['content']),
        options: options,
        raw: params,
      ),
    );
  }

  /// Decodes an ACP `session/update` params map into a typed [KimiEvent].
  /// Exposed for testing; production traffic flows through the same path.
  @visibleForTesting
  static KimiEvent decodeSessionUpdate(Map<String, Object?> params) {
    final update = params['update'];
    final u = update is Map<String, Object?> ? update : const <String, Object?>{};
    final type = u['sessionUpdate']?.toString() ?? '';
    switch (type) {
      case 'agent_message_chunk':
      case 'agent_thought_chunk':
      case 'user_message_chunk':
        final content = u['content'];
        final contentMap = content is Map<String, Object?>
            ? content
            : const <String, Object?>{};
        final isText = contentMap['type'] == 'text';
        return ContentPartEvent(
          kind: !isText
              ? ContentKind.other
              : type == 'agent_thought_chunk'
                  ? ContentKind.thinking
                  : type == 'agent_message_chunk'
                      ? ContentKind.text
                      : ContentKind.other,
          text: contentMap['text']?.toString() ?? '',
          rawType: type,
          raw: u,
        );
      case 'tool_call':
        final rawInput = u['rawInput'];
        return ToolCallEvent(
          id: u['toolCallId']?.toString() ?? '',
          name: u['title']?.toString() ?? '',
          kind: u['kind']?.toString(),
          status: u['status']?.toString(),
          arguments: rawInput == null ? null : jsonEncode(rawInput),
          raw: u,
        );
      case 'tool_call_update':
        final status = u['status']?.toString();
        final text = _contentText(u['content']);
        if (status == 'completed' || status == 'failed') {
          final rawOutput = u['rawOutput'];
          return ToolResultEvent(
            toolCallId: u['toolCallId']?.toString() ?? '',
            isError: status == 'failed',
            output: rawOutput?.toString() ?? text,
            raw: u,
          );
        }
        return ToolCallUpdateEvent(
          toolCallId: u['toolCallId']?.toString() ?? '',
          status: status,
          text: text,
          raw: u,
        );
      case 'plan':
        return PlanEvent(
          entries: [
            for (final e in u['entries'] as List? ?? const [])
              if (e is Map<String, Object?>) e,
          ],
          raw: u,
        );
      default:
        return UnknownEvent(type: type, raw: u);
    }
  }

  /// Flattens an ACP tool-call `content` list to its text parts.
  static String _contentText(Object? content) {
    if (content is! List) return '';
    final buffer = StringBuffer();
    for (final item in content) {
      if (item is! Map<String, Object?>) continue;
      final inner = item['type'] == 'content' ? item['content'] : item;
      if (inner is Map<String, Object?> && inner['type'] == 'text') {
        buffer.write(inner['text'] ?? '');
      }
    }
    return buffer.toString();
  }

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
