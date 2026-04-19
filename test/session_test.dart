import 'package:flutter_kimi_sdk/flutter_kimi_sdk.dart';
import 'package:test/test.dart';

void main() {
  group('KimiTurnStatus.parse', () {
    test('maps known statuses', () {
      expect(KimiTurnStatus.parse('finished'), KimiTurnStatus.finished);
      expect(KimiTurnStatus.parse('cancelled'), KimiTurnStatus.cancelled);
      expect(KimiTurnStatus.parse('max_steps_reached'),
          KimiTurnStatus.maxStepsReached);
    });

    test('falls back to unknown', () {
      expect(KimiTurnStatus.parse('wat'), KimiTurnStatus.unknown);
      expect(KimiTurnStatus.parse(''), KimiTurnStatus.unknown);
    });
  });

  group('ApprovalResponse', () {
    test('wire values', () {
      expect(ApprovalResponse.approve.wireValue, 'approve');
      expect(ApprovalResponse.approveForSession.wireValue, 'approve_for_session');
      expect(ApprovalResponse.reject.wireValue, 'reject');
    });
  });

  group('event decoding', () {
    // We can't spawn a real CLI in unit tests, but we can drive the decoder
    // directly via a dedicated test hook to confirm wire payload shapes map
    // onto the right event types.
    Future<KimiSession> startFake() => KimiSession.start(
          workDir: '.',
          executable: '/bin/cat', // never speaks wire protocol; we never prompt
        );

    test('decodes ContentPart text', () async {
      final session = await startFake();
      addTearDown(session.close);
      final event = session.decodeEventForTest(
        'ContentPart',
        <String, Object?>{'type': 'text', 'text': 'hello'},
      );
      expect(event, isA<ContentPartEvent>());
      final e = event as ContentPartEvent;
      expect(e.kind, ContentKind.text);
      expect(e.text, 'hello');
    });

    test('decodes ToolCall', () async {
      final session = await startFake();
      addTearDown(session.close);
      final event = session.decodeEventForTest(
        'ToolCall',
        <String, Object?>{
          'type': 'function',
          'id': 'tc_1',
          'function': {'name': 'shell', 'arguments': '{"cmd":"ls"}'},
        },
      );
      expect(event, isA<ToolCallEvent>());
      final e = event as ToolCallEvent;
      expect(e.id, 'tc_1');
      expect(e.name, 'shell');
      expect(e.arguments, '{"cmd":"ls"}');
    });

    test('decodes unknown as UnknownEvent', () async {
      final session = await startFake();
      addTearDown(session.close);
      final event = session.decodeEventForTest(
        'SomethingNew',
        <String, Object?>{'x': 1},
      );
      expect(event, isA<UnknownEvent>());
      expect((event as UnknownEvent).type, 'SomethingNew');
    });
  });
}
