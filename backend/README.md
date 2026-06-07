# cc-mimo-rescue backend

Backend-only MVP for Claude Code + CC Switch + Xiaomi MiMo rescue/configuration.

## Run from source

```bash
PYTHONPATH=src python3 -m cc_mimo_rescue --version
PYTHONPATH=src python3 -m cc_mimo_rescue doctor --json
```

## Commands

```bash
# Discover local Claude Code and CC Switch paths.
PYTHONPATH=src python3 -m cc_mimo_rescue init --json

# Inspect current environment.
PYTHONPATH=src python3 -m cc_mimo_rescue doctor --json

# List recent Claude Code sessions.
PYTHONPATH=src python3 -m cc_mimo_rescue sessions list --limit 20 --json

# Preview cleanup for a session.
PYTHONPATH=src python3 -m cc_mimo_rescue sessions preview-clean --session <session-id> --json

# Apply cleanup only when explicitly confirmed.
PYTHONPATH=src python3 -m cc_mimo_rescue sessions clean --session <session-id> --yes --json

# Preview CC Switch model mapping.
PYTHONPATH=src python3 -m cc_mimo_rescue configure preview --json

# Apply CC Switch model mapping only when explicitly confirmed.
PYTHONPATH=src python3 -m cc_mimo_rescue configure apply --yes --json

# Preview or apply the managed Claude memory block.
PYTHONPATH=src python3 -m cc_mimo_rescue configure memory-preview --json
PYTHONPATH=src python3 -m cc_mimo_rescue configure memory-apply --yes --json

# List/restore backups.
PYTHONPATH=src python3 -m cc_mimo_rescue backups list --json
PYTHONPATH=src python3 -m cc_mimo_rescue backups create-sessions --yes --json
PYTHONPATH=src python3 -m cc_mimo_rescue backups restore --backup <backup-id> --yes --json
```

## Safety defaults

- Session cleaning is dry-run unless `--yes` is passed.
- CC Switch configuration is dry-run unless `--yes` is passed.
- Memory injection is dry-run unless `--yes` is passed.
- Full chat-record backup is dry-run unless `--yes` is passed.
- Every write creates a backup under `~/.local/share/cc-mimo-rescue/backups`.
- Audit events are written under `~/.local/share/cc-mimo-rescue/audit`.
- CC Switch auth tokens are never printed; only `hasAuthToken` is shown.
- The backend is local-only and has no telemetry/upload service.

## Current scope

Implemented:

- path discovery,
- local config generation,
- doctor report,
- session list,
- risk scoring for image paths/media/base64-like blocks,
- cleanup preview,
- cleanup apply with backup,
- backup list, full local chat-record backup, and single-file restore,
- CC Switch inspect/preview/apply for current Claude provider,
- managed memory preview/apply.

Not implemented yet:

- Claude probe skill execution,
- OCR/image summarization backend,
- packaged installer.
