/// Dart client for the Kimi Agent SDK.
///
/// Spawns the `kimi` CLI with its wire protocol and exposes a typed streaming
/// API. Works anywhere `dart:io` can spawn a process (desktop, server, Flutter
/// desktop); not supported on iOS, Android, or web.
///
/// ```dart
/// final session = KimiSession.start(
///   workDir: Directory.current.path,
///   model: 'kimi-k2-thinking-turbo',
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
