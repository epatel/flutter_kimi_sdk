// Smoke test against a real `kimi` CLI: one yolo-mode turn with a tool call,
// then a second turn exercising the manual approval path.
//
// Run: dart run tool/acp_smoke.dart [workDir]
import 'dart:io';

import 'package:flutter_kimi_sdk/flutter_kimi_sdk.dart';

Future<void> main(List<String> args) async {
  final workDir = args.isNotEmpty ? args.first : Directory.current.path;
  final verbose = Platform.environment['SMOKE_VERBOSE'] == '1';

  stdout.writeln('=== turn 1: yoloMode ===');
  var session = await KimiSession.start(
    workDir: workDir,
    yoloMode: true,
    onWire: verbose ? (d, j) => stderr.writeln('[$d] $j') : null,
  );
  try {
    final info = await session.initialize();
    stdout.writeln('session: ${session.acpSessionId}');
    stdout.writeln('configOptions ids: '
        '${(info['configOptions'] as List? ?? []).map((o) => (o as Map)['id']).join(', ')}');
    final turn = session.prompt(
        'Run `echo smoke-yolo` in the shell, then reply with exactly: OK1');
    await for (final event in turn.events) {
      switch (event) {
        case ContentPartEvent(:final kind, :final text)
            when kind == ContentKind.text:
          stdout.write(text);
        case ToolCallEvent(:final name, :final kind):
          stdout.writeln('\n[tool_call] $name ($kind)');
        case ToolResultEvent(:final isError, :final output):
          stdout.writeln('[tool_result] error=$isError output=${output.trim()}');
        case ApprovalRequestEvent():
          stdout.writeln('[UNEXPECTED approval in yolo mode]');
        default:
          break;
      }
    }
    final result = await turn.result;
    stdout.writeln('\nresult: $result');
  } finally {
    await session.close();
  }

  stdout.writeln('\n=== turn 2: manual approval ===');
  session = await KimiSession.start(workDir: workDir);
  try {
    await session.initialize();
    final turn = session.prompt(
        'Run `echo smoke-approved` in the shell, then reply with exactly: OK2');
    await for (final event in turn.events) {
      switch (event) {
        case ContentPartEvent(:final kind, :final text)
            when kind == ContentKind.text:
          stdout.write(text);
        case ApprovalRequestEvent(:final id, :final sender, :final description):
          stdout.writeln('\n[approval] $sender: $description -> approving');
          await turn.approve(id, ApprovalResponse.approve);
        case ToolResultEvent(:final isError, :final output):
          stdout.writeln('[tool_result] error=$isError output=${output.trim()}');
        default:
          break;
      }
    }
    final result = await turn.result;
    stdout.writeln('\nresult: $result');
  } finally {
    await session.close();
  }
}
