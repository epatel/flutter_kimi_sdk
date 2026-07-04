/// Dart client for the Kimi Code CLI.
///
/// Spawns `kimi acp` — the CLI's Agent Client Protocol (ACP) server — and
/// exposes a typed streaming API. Works anywhere `dart:io` can spawn a
/// process (desktop, server, Flutter desktop); not supported on iOS,
/// Android, or web.
///
/// ```dart
/// final session = KimiSession.start(
///   workDir: Directory.current.path,
///   yoloMode: true,
/// );
/// await session.initialize();
/// final turn = session.prompt('Hello');
/// await for (final event in turn.events) {
///   if (event is ContentPartEvent && event.kind == ContentKind.text) {
///     stdout.write(event.text);
///   }
/// }
/// final result = await turn.result;
/// await session.close();
/// ```
library;

export 'src/errors.dart';
export 'src/events.dart';
export 'src/session.dart';
export 'src/types.dart';
