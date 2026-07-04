import 'package:flutter_kimi_sdk/flutter_kimi_sdk.dart';
import 'package:test/test.dart';

Map<String, Object?> update(Map<String, Object?> u) => <String, Object?>{
      'sessionId': 'session_test',
      'update': u,
    };

void main() {
  group('KimiTurnStatus.parse', () {
    test('maps ACP stop reasons', () {
      expect(KimiTurnStatus.parse('end_turn'), KimiTurnStatus.finished);
      expect(KimiTurnStatus.parse('cancelled'), KimiTurnStatus.cancelled);
      expect(KimiTurnStatus.parse('max_turn_requests'),
          KimiTurnStatus.maxStepsReached);
      expect(KimiTurnStatus.parse('max_tokens'), KimiTurnStatus.maxTokens);
      expect(KimiTurnStatus.parse('refusal'), KimiTurnStatus.refusal);
    });

    test('falls back to unknown', () {
      expect(KimiTurnStatus.parse('wat'), KimiTurnStatus.unknown);
      expect(KimiTurnStatus.parse(''), KimiTurnStatus.unknown);
    });
  });

  group('ApprovalResponse', () {
    test('option kinds', () {
      expect(ApprovalResponse.approve.optionKind, 'allow_once');
      expect(ApprovalResponse.approveForSession.optionKind, 'allow_always');
      expect(ApprovalResponse.reject.optionKind, 'reject_once');
    });
  });

  group('session update decoding', () {
    test('decodes agent_message_chunk as text', () {
      final event = KimiSession.decodeSessionUpdate(update({
        'sessionUpdate': 'agent_message_chunk',
        'content': {'type': 'text', 'text': 'hello'},
      }));
      expect(event, isA<ContentPartEvent>());
      final e = event as ContentPartEvent;
      expect(e.kind, ContentKind.text);
      expect(e.text, 'hello');
    });

    test('decodes agent_thought_chunk as thinking', () {
      final event = KimiSession.decodeSessionUpdate(update({
        'sessionUpdate': 'agent_thought_chunk',
        'content': {'type': 'text', 'text': 'hmm'},
      }));
      final e = event as ContentPartEvent;
      expect(e.kind, ContentKind.thinking);
      expect(e.text, 'hmm');
    });

    test('decodes tool_call', () {
      final event = KimiSession.decodeSessionUpdate(update({
        'sessionUpdate': 'tool_call',
        'toolCallId': '0:tool_abc',
        'title': 'Bash',
        'kind': 'execute',
        'status': 'pending',
      }));
      expect(event, isA<ToolCallEvent>());
      final e = event as ToolCallEvent;
      expect(e.id, '0:tool_abc');
      expect(e.name, 'Bash');
      expect(e.kind, 'execute');
      expect(e.status, 'pending');
      expect(e.arguments, isNull);
    });

    test('decodes in-progress tool_call_update as ToolCallUpdateEvent', () {
      final event = KimiSession.decodeSessionUpdate(update({
        'sessionUpdate': 'tool_call_update',
        'toolCallId': '0:tool_abc',
        'status': 'in_progress',
        'content': [
          {
            'type': 'content',
            'content': {'type': 'text', 'text': '{"cmd":'},
          },
        ],
      }));
      expect(event, isA<ToolCallUpdateEvent>());
      final e = event as ToolCallUpdateEvent;
      expect(e.toolCallId, '0:tool_abc');
      expect(e.status, 'in_progress');
      expect(e.text, '{"cmd":');
    });

    test('decodes completed tool_call_update as ToolResultEvent', () {
      final event = KimiSession.decodeSessionUpdate(update({
        'sessionUpdate': 'tool_call_update',
        'toolCallId': '0:tool_abc',
        'status': 'completed',
        'content': [
          {
            'type': 'content',
            'content': {'type': 'text', 'text': 'hello-acp\n'},
          },
        ],
        'rawOutput': 'hello-acp\n',
      }));
      expect(event, isA<ToolResultEvent>());
      final e = event as ToolResultEvent;
      expect(e.toolCallId, '0:tool_abc');
      expect(e.isError, isFalse);
      expect(e.output, 'hello-acp\n');
    });

    test('decodes failed tool_call_update as error ToolResultEvent', () {
      final event = KimiSession.decodeSessionUpdate(update({
        'sessionUpdate': 'tool_call_update',
        'toolCallId': '0:tool_abc',
        'status': 'failed',
        'content': [
          {
            'type': 'content',
            'content': {'type': 'text', 'text': 'boom'},
          },
        ],
      }));
      final e = event as ToolResultEvent;
      expect(e.isError, isTrue);
      expect(e.output, 'boom');
    });

    test('decodes plan', () {
      final event = KimiSession.decodeSessionUpdate(update({
        'sessionUpdate': 'plan',
        'entries': [
          {'content': 'step 1', 'priority': 'high', 'status': 'pending'},
        ],
      }));
      expect(event, isA<PlanEvent>());
      expect((event as PlanEvent).entries, hasLength(1));
      expect(event.entries.first['content'], 'step 1');
    });

    test('decodes unknown update types as UnknownEvent', () {
      final event = KimiSession.decodeSessionUpdate(update({
        'sessionUpdate': 'available_commands_update',
        'availableCommands': <Object>[],
      }));
      expect(event, isA<UnknownEvent>());
      expect((event as UnknownEvent).type, 'available_commands_update');
    });
  });
}
