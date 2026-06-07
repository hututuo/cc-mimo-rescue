from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Any, Dict, Optional

from . import __version__
from .audit import write_audit
from .backup import create_session_full_backup, list_backups, restore_backup
from .ccswitch import MODEL_KEY_BY_SLOT, apply_configure, inspect as inspect_ccswitch, preview_configure
from .discovery import discover, write_config
from .doctor import run_doctor
from .memory import apply_memory, preview_memory, reset_memory
from .sessions import apply_clean, count_transcripts, preview_clean, scan_sessions
from .utils import print_json


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="cc-mimo-rescue")
    parser.add_argument("--version", action="version", version=__version__)
    parser.add_argument("--json", action="store_true", help="Emit JSON output.")
    sub = parser.add_subparsers(dest="command", required=True)

    init = sub.add_parser("init", help="Discover local paths and write config.")
    add_common(init)
    doctor = sub.add_parser("doctor", help="Inspect Claude Code and CC Switch state.")
    add_common(doctor)

    sessions = sub.add_parser("sessions", help="List, preview, or clean Claude Code sessions.")
    add_common(sessions)
    sess_sub = sessions.add_subparsers(dest="sessions_command", required=True)
    sess_list = sess_sub.add_parser("list")
    add_common(sess_list)
    sess_list.add_argument("--project", help="Filter by project path/key substring.")
    sess_list.add_argument("--limit", type=int, default=50)
    sess_list.add_argument("--risk", choices=["ok", "warning", "danger"])
    preview = sess_sub.add_parser("preview-clean")
    add_common(preview)
    preview.add_argument("--session")
    preview.add_argument("--transcript")
    preview.add_argument("--mode", default="replace-media-with-placeholder")
    clean = sess_sub.add_parser("clean")
    add_common(clean)
    clean.add_argument("--session")
    clean.add_argument("--transcript")
    clean.add_argument("--mode", default="replace-media-with-placeholder")
    clean.add_argument("--yes", action="store_true", help="Actually write cleaned transcript.")

    configure = sub.add_parser("configure", help="Preview/apply CC Switch and memory configuration.")
    add_common(configure)
    conf_sub = configure.add_subparsers(dest="configure_command", required=True)
    conf_preview = conf_sub.add_parser("preview")
    add_common(conf_preview)
    add_route_args(conf_preview)
    conf_apply = conf_sub.add_parser("apply")
    add_common(conf_apply)
    add_route_args(conf_apply)
    conf_apply.add_argument("--yes", action="store_true")
    mem_preview = conf_sub.add_parser("memory-preview")
    add_common(mem_preview)
    mem_preview.add_argument("--path")
    mem_preview.add_argument("--image-model", default="mimo-v2.5")
    mem_preview.add_argument("--helper-model", default="haiku", choices=["haiku", "sonnet", "opus", "main"])
    mem_apply = conf_sub.add_parser("memory-apply")
    add_common(mem_apply)
    mem_apply.add_argument("--path")
    mem_apply.add_argument("--image-model", default="mimo-v2.5")
    mem_apply.add_argument("--helper-model", default="haiku", choices=["haiku", "sonnet", "opus", "main"])
    mem_apply.add_argument("--yes", action="store_true")
    mem_reset = conf_sub.add_parser("memory-reset")
    add_common(mem_reset)
    mem_reset.add_argument("--path")
    mem_reset.add_argument("--yes", action="store_true")
    inspect = conf_sub.add_parser("inspect-ccswitch")
    add_common(inspect)

    backups = sub.add_parser("backups", help="List or restore backups.")
    add_common(backups)
    bak_sub = backups.add_subparsers(dest="backups_command", required=True)
    bak_list = bak_sub.add_parser("list")
    add_common(bak_list)
    create_sessions = bak_sub.add_parser("create-sessions")
    add_common(create_sessions)
    create_sessions.add_argument("--yes", action="store_true")
    restore = bak_sub.add_parser("restore")
    add_common(restore)
    restore.add_argument("--backup", required=True)
    restore.add_argument("--yes", action="store_true")
    return parser


def add_common(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--json", action="store_true", default=argparse.SUPPRESS, help=argparse.SUPPRESS)


def add_route_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--image-model", default="mimo-v2.5")
    parser.add_argument("--main-model", default="mimo-v2.5-pro[1m]")
    parser.add_argument("--haiku-model")
    parser.add_argument("--sonnet-model")
    parser.add_argument("--opus-model")
    parser.add_argument("--default-model")


def main(argv: Optional[list[str]] = None) -> int:
    try:
        return _main(argv)
    except SystemExit:
        raise
    except Exception as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


def _main(argv: Optional[list[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    discovery = discover()

    if args.command == "init":
        path = write_config(discovery)
        return emit(args, {"config": str(path), "discovery": discovery.to_dict()})

    if args.command == "doctor":
        return emit(args, run_doctor(discovery))

    if args.command == "sessions":
        return handle_sessions(args, discovery)

    if args.command == "configure":
        return handle_configure(args, discovery)

    if args.command == "backups":
        if args.backups_command == "list":
            return emit(args, {"backups": list_backups()})
        if args.backups_command == "create-sessions":
            if not args.yes:
                return emit(args, {
                    "applied": False,
                    "message": "dry run; pass --yes to create a full local session backup",
                    "projects_dir": discovery.claude_projects_dir,
                    "sessions_dir": discovery.claude_sessions_dir,
                    "privacy": "local-only; no network upload; no telemetry",
                })
            result = create_session_full_backup(
                Path(discovery.claude_projects_dir),
                Path(discovery.claude_sessions_dir),
            )
            write_audit(
                {
                    "command": "backups create-sessions",
                    "dryRun": False,
                    "targetKind": "sessions",
                    "targetPath": discovery.claude_projects_dir,
                    "backupId": result.get("backup_id"),
                    "changed": True,
                    "summary": "create full local Claude session backup",
                    "redactionsApplied": [],
                }
            )
            return emit(args, {**result, "applied": True})
        if args.backups_command == "restore":
            result = restore_backup(args.backup, apply=args.yes)
            write_audit(
                {
                    "command": "backups restore",
                    "dryRun": not args.yes,
                    "targetKind": "config",
                    "backupId": args.backup,
                    "changed": bool(args.yes),
                    "summary": "restore backup",
                    "redactionsApplied": [],
                }
            )
            return emit(args, result)

    parser.error("unhandled command")
    return 2


def handle_sessions(args: argparse.Namespace, discovery: Any) -> int:
    projects_dir = Path(discovery.claude_projects_dir)
    sessions_dir = Path(discovery.claude_sessions_dir)
    if args.sessions_command == "list":
        summaries = scan_sessions(
            projects_dir,
            sessions_dir,
            project_filter=args.project,
            limit=args.limit,
            risk_filter=args.risk,
        )
        total = count_transcripts(projects_dir, args.project)
        return emit(args, {"sessions": [s.to_dict() for s in summaries], "count": len(summaries), "total": total})

    transcript = resolve_transcript(args, discovery)
    if args.sessions_command == "preview-clean":
        return emit(args, preview_clean(transcript, args.mode))
    if args.sessions_command == "clean":
        result = apply_clean(transcript, args.mode, yes=args.yes)
        write_audit(
            {
                "command": "sessions clean",
                "dryRun": not args.yes,
                "targetKind": "session",
                "targetPath": str(transcript),
                "backupId": result.get("backup"),
                "changed": bool(result.get("applied")),
                "summary": f"session clean mode={args.mode}",
                "redactionsApplied": [],
            }
        )
        return emit(args, result)
    return 2


def handle_configure(args: argparse.Namespace, discovery: Any) -> int:
    db = Path(discovery.cc_switch_db)
    settings = Path(discovery.cc_switch_settings)
    if args.configure_command == "inspect-ccswitch":
        return emit(args, inspect_ccswitch(db))
    if args.configure_command == "preview":
        return emit(args, preview_configure(db, args.image_model, args.main_model, route_overrides(args)))
    if args.configure_command == "apply":
        result = apply_configure(db, settings, args.image_model, args.main_model, yes=args.yes, model_overrides=route_overrides(args))
        write_audit(
            {
                "command": "configure apply",
                "dryRun": not args.yes,
                "targetKind": "ccswitch",
                "targetPath": str(db),
                "backupId": result.get("backup"),
                "changed": bool(result.get("applied")),
                "summary": "patch CC Switch MiMo model routing",
                "redactionsApplied": ["settings_config.env.*token*"],
            }
        )
        return emit(args, result)
    if args.configure_command == "memory-preview":
        path = Path(args.path or discovery.claude_global_memory).expanduser()
        return emit(args, preview_memory(path, image_model=args.image_model, helper_model=args.helper_model))
    if args.configure_command == "memory-apply":
        path = Path(args.path or discovery.claude_global_memory).expanduser()
        result = apply_memory(path, yes=args.yes, image_model=args.image_model, helper_model=args.helper_model)
        write_audit(
            {
                "command": "configure memory-apply",
                "dryRun": not args.yes,
                "targetKind": "memory",
                "targetPath": str(path),
                "backupId": result.get("backup"),
                "changed": bool(result.get("applied")),
                "summary": "inject managed image-routing memory block",
                "redactionsApplied": [],
            }
        )
        return emit(args, result)
    if args.configure_command == "memory-reset":
        path = Path(args.path or discovery.claude_global_memory).expanduser()
        result = reset_memory(path, yes=args.yes)
        write_audit(
            {
                "command": "configure memory-reset",
                "dryRun": not args.yes,
                "targetKind": "memory",
                "targetPath": str(path),
                "backupId": result.get("backup"),
                "changed": bool(result.get("applied")),
                "summary": "remove managed image-routing memory block",
                "redactionsApplied": [],
            }
        )
        return emit(args, result)
    return 2


def route_overrides(args: argparse.Namespace) -> Optional[Dict[str, str]]:
    values = {
        MODEL_KEY_BY_SLOT["haiku"]: getattr(args, "haiku_model", None),
        MODEL_KEY_BY_SLOT["sonnet"]: getattr(args, "sonnet_model", None),
        MODEL_KEY_BY_SLOT["opus"]: getattr(args, "opus_model", None),
        MODEL_KEY_BY_SLOT["main"]: getattr(args, "default_model", None),
    }
    overrides = {k: v for k, v in values.items() if v}
    return overrides or None


def resolve_transcript(args: argparse.Namespace, discovery: Any) -> Path:
    if getattr(args, "transcript", None):
        return Path(args.transcript).expanduser()
    if not getattr(args, "session", None):
        raise SystemExit("provide --session or --transcript")
    matches = list(Path(discovery.claude_projects_dir).glob(f"*/{args.session}.jsonl"))
    if len(matches) != 1:
        raise SystemExit(f"expected one transcript for session {args.session}, found {len(matches)}")
    return matches[0]


def emit(args: argparse.Namespace, data: Dict[str, Any]) -> int:
    if getattr(args, "json", False):
        print_json(data)
    else:
        print_human(data)
    return 0


def print_human(data: Dict[str, Any]) -> None:
    print_json(data)
