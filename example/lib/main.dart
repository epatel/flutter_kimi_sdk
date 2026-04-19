import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_kimi_sdk/flutter_kimi_sdk.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

void main() {
  runApp(const KimiExampleApp());
}

class KimiExampleApp extends StatelessWidget {
  const KimiExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kimi SDK demo',
      theme: ThemeData(colorSchemeSeed: Colors.deepPurple, useMaterial3: true),
      home: const ChatPage(),
    );
  }
}

class _Message {
  _Message({required this.role, required this.text});
  final String role; // 'user' | 'assistant' | 'tool' | 'system'
  String text;
}

String _resolveKimiExecutable() {
  final override = Platform.environment['KIMI_EXECUTABLE'];
  if (override != null && override.isNotEmpty) return override;
  final home = Platform.environment['HOME'];
  if (home != null) {
    for (final candidate in [
      '$home/.local/bin/kimi',
      '/opt/homebrew/bin/kimi',
      '/usr/local/bin/kimi',
    ]) {
      if (File(candidate).existsSync()) return candidate;
    }
  }
  return 'kimi';
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _input = TextEditingController();
  final List<_Message> _messages = [];
  final List<String> _debug = [];
  KimiSession? _session;
  KimiTurn? _turn;
  bool _busy = false;
  bool _showDebug = false;
  String _status = 'not started';

  void _log(String line) {
    if (!mounted) return;
    setState(() {
      _debug.add(line);
      if (_debug.length > 400) _debug.removeRange(0, _debug.length - 400);
    });
  }

  @override
  void dispose() {
    unawaited(_session?.close());
    _input.dispose();
    super.dispose();
  }

  Future<void> _startSession() async {
    setState(() {
      _busy = true;
      _status = 'spawning kimi...';
    });
    try {
      final exe = _resolveKimiExecutable();
      _log('[sys] executable: $exe');
      _log('[sys] workDir: ${Directory.current.path}');
      final session = await KimiSession.start(
        workDir: Directory.current.path,
        executable: exe,
        model: Platform.environment['KIMI_MODEL_NAME'],
        yoloMode: false,
        onStderr: (line) => _log('[stderr] $line'),
        onWire: (dir, json) => _log('[$dir] $json'),
      );
      await session.initialize();
      setState(() {
        _session = session;
        _status = 'ready';
      });
    } on KimiException catch (e) {
      setState(() {
        _status = 'error: $e';
        _messages.add(_Message(role: 'system', text: e.toString()));
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    final session = _session;
    final text = _input.text.trim();
    if (session == null || text.isEmpty || _busy) return;
    _input.clear();

    setState(() {
      _messages.add(_Message(role: 'user', text: text));
      _messages.add(_Message(role: 'assistant', text: ''));
      _busy = true;
      _status = 'thinking...';
    });

    final turn = session.prompt(text);
    _turn = turn;
    _Message assistantMsg = _messages.last;

    turn.events.listen((event) {
      if (!mounted) return;
      setState(() {
        if (event is ContentPartEvent && event.kind == ContentKind.text) {
          assistantMsg.text += event.text;
        } else if (event is ToolCallEvent) {
          _messages.add(
            _Message(
              role: 'tool',
              text: '→ ${event.name}(${event.arguments ?? ''})',
            ),
          );
          assistantMsg = _Message(role: 'assistant', text: '');
          _messages.add(assistantMsg);
        } else if (event is ToolResultEvent) {
          _messages.add(
            _Message(
              role: 'tool',
              text: event.isError
                  ? '✗ error: ${event.message}'
                  : '✓ ${event.message}',
            ),
          );
          assistantMsg = _Message(role: 'assistant', text: '');
          _messages.add(assistantMsg);
        } else if (event is ApprovalRequestEvent) {
          _handleApproval(turn, event);
        } else if (event is StatusUpdateEvent) {
          _status =
              'tokens in=${event.inputTokens ?? '-'} out=${event.outputTokens ?? '-'}';
        }
      });
    });

    try {
      final result = await turn.result;
      if (!mounted) return;
      setState(() {
        _status = 'done (${result.status.name}, steps=${result.steps ?? '-'})';
        _busy = false;
      });
    } on KimiException catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(_Message(role: 'system', text: 'Error: $e'));
        _status = 'error';
        _busy = false;
      });
    }
  }

  Future<void> _handleApproval(
      KimiTurn turn, ApprovalRequestEvent event) async {
    final decision = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${event.sender}: ${event.action}?'),
        content: Text(event.description),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Deny'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    await turn.approve(
      event.id,
      decision == true ? ApprovalResponse.approve : ApprovalResponse.reject,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kimi SDK demo'),
        actions: [
          if (_session == null)
            TextButton(
              onPressed: _busy ? null : _startSession,
              child: const Text('Start session'),
            )
          else if (_busy && _turn != null)
            IconButton(
              tooltip: 'Interrupt',
              icon: const Icon(Icons.stop_circle_outlined),
              onPressed: () => _turn?.interrupt(),
            ),
          IconButton(
            tooltip: 'Toggle debug log',
            icon: Icon(_showDebug ? Icons.bug_report : Icons.bug_report_outlined),
            onPressed: () => setState(() => _showDebug = !_showDebug),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(
              child: Text(
                _status,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SelectionArea(
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _messages.length,
                itemBuilder: (context, i) => _MessageBubble(msg: _messages[i]),
              ),
            ),
          ),
          if (_showDebug)
            SizedBox(
              height: 180,
              child: Container(
                color: Colors.black.withValues(alpha: 0.85),
                padding: const EdgeInsets.all(8),
                child: SelectionArea(
                  child: ListView.builder(
                    reverse: false,
                    itemCount: _debug.length,
                    itemBuilder: (ctx, i) => Text(
                      _debug[i],
                      style: const TextStyle(
                        fontFamily: 'Menlo',
                        fontSize: 11,
                        color: Colors.greenAccent,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    enabled: _session != null && !_busy,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(
                      hintText: 'Ask Kimi something...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _session != null && !_busy ? _send : null,
                  child: const Text('Send'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.msg});
  final _Message msg;

  bool get _useMarkdown => msg.role == 'assistant' || msg.role == 'user';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (Color bg, Color fg, Alignment align) = switch (msg.role) {
      'user' => (
          theme.colorScheme.primaryContainer,
          theme.colorScheme.onPrimaryContainer,
          Alignment.centerRight
        ),
      'assistant' => (
          theme.colorScheme.surfaceContainerHighest,
          theme.colorScheme.onSurface,
          Alignment.centerLeft
        ),
      'tool' => (
          theme.colorScheme.tertiaryContainer,
          theme.colorScheme.onTertiaryContainer,
          Alignment.centerLeft
        ),
      _ => (
          theme.colorScheme.errorContainer,
          theme.colorScheme.onErrorContainer,
          Alignment.center
        ),
    };
    if (msg.text.isEmpty) return const SizedBox.shrink();
    final Widget content = _useMarkdown
        ? MarkdownBody(
            data: msg.text,
            selectable: false, // outer SelectionArea handles selection
            styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
              p: theme.textTheme.bodyMedium?.copyWith(color: fg),
              h1: theme.textTheme.headlineSmall?.copyWith(color: fg),
              h2: theme.textTheme.titleLarge?.copyWith(color: fg),
              h3: theme.textTheme.titleMedium?.copyWith(color: fg),
              listBullet: TextStyle(color: fg),
              code: TextStyle(
                color: fg,
                fontFamily: 'Menlo',
                backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.5),
              ),
              codeblockDecoration: BoxDecoration(
                color: theme.colorScheme.surface.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(6),
              ),
              blockquoteDecoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: fg.withValues(alpha: 0.5), width: 3),
                ),
              ),
            ),
          )
        : Text(
            msg.text,
            style: TextStyle(color: fg, fontFamily: 'Menlo', fontSize: 12),
          );
    return Align(
      alignment: align,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 720),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: fg),
          child: content,
        ),
      ),
    );
  }
}
