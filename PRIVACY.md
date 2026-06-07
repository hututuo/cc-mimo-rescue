# Privacy

CC MiMo Rescue is designed as a local-only utility.

## Network

The app does not upload chat records, backups, configuration, tokens, paths, or audit logs.

The current backend has no dependency on a hosted service and uses only local filesystem access plus local subprocess calls needed to run the bundled Python CLI.

## Local Files Read

Depending on the action the user chooses, the app may read:

- Claude Code config and memory paths,
- Claude transcript files under `~/.claude/projects`,
- active session metadata under `~/.claude/sessions`,
- CC Switch local database/settings,
- cc-mimo-rescue backups and audit logs.

## Local Files Written

Writes happen only after explicit confirmation for actions such as:

- creating a full local chat-record backup,
- repairing a selected transcript,
- updating CC Switch model routes,
- applying or resetting the managed Claude memory block,
- restoring a single-file backup.

Backups and audit logs are stored under:

```text
~/.local/share/cc-mimo-rescue
```

## Tokens And Secrets

The backend redacts sensitive keys in audit-style data and does not print CC Switch auth tokens. Provider reports expose only whether a token exists.

## User Responsibility

If you publish screenshots, logs, backups, or transcript samples, review them first. Claude transcripts and backups can contain private conversation content.
