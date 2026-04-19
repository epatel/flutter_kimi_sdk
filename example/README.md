# flutter_kimi_sdk example

A minimal Flutter **desktop** chat UI that talks to the Kimi Code CLI through
`flutter_kimi_sdk`.

## Run

```bash
# From the example/ directory:
flutter create --platforms=macos,linux,windows .   # scaffold desktop runners
flutter run -d macos    # or linux / windows
```

### Requirements

- `kimi` CLI on your `PATH`.
- Authenticate the CLI once with `kimi login` (credentials are stored in
  `~/.kimi/config.toml` and reused automatically). Alternatively export
  `KIMI_API_KEY` / `KIMI_BASE_URL` / `KIMI_MODEL_NAME` in the environment you
  launch Flutter from.

The app starts paused — hit **Start session** to spawn the CLI. Each prompt
creates a new `KimiTurn`; tool calls render as chips, and approval requests
pop a dialog.

## CLI-only variant

If you just want a non-Flutter smoke test:

```bash
dart run ../lib/flutter_kimi_sdk.dart  # (library only — see README quick start)
```

The package README's Quick Start snippet is a 20-line pure-Dart CLI that works
without Flutter installed.
