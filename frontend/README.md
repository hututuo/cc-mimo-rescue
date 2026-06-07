# CC MiMo Rescue UI

Native macOS SwiftUI frontend for the `cc-mimo-rescue` Python backend.

## Run From Source

```bash
cd frontend
swift run CCMimoRescueUI
```

The app finds the backend in this order:

1. `CC_MIMO_RESCUE_BACKEND`
2. `CC MiMo Rescue.app/Contents/Resources/backend`
3. sibling source folders such as `../backend`
4. the local development fallback path

## Build

```bash
cd frontend
swift build
```

## Package A Local App

```bash
cd frontend
scripts/package-app.sh
```

This creates:

```text
frontend/dist/CC MiMo Rescue.app
```

The package script bundles:

- the SwiftUI executable,
- `Resources/AppIcon.icns`,
- the Python backend source,
- backend resources such as the memory snippet and Claude probe skill.

The bundled app still uses the system Python at `/usr/bin/python3`. A future installer can replace this with a managed Python runtime.

## Current Screens

- Health
- Sessions
- Repair
- Configure
- Backups
- Settings
- Logs

The UI supports runtime language switching between English and Chinese from the top bar and Settings. The selection is stored in user defaults under `cc-mimo-rescue.language`.
Chinese is the default language for first launch.

Dangerous writes still go through backend commands that require explicit `--yes`, and the UI presents confirmation dialogs before calling those commands.

The app is local-only. It does not upload transcripts, backups, tokens, or telemetry.
