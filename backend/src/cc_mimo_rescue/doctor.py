from __future__ import annotations

from pathlib import Path
from typing import Any, Dict

from .ccswitch import inspect as inspect_ccswitch
from .discovery import Discovery
from .sessions import scan_sessions


def run_doctor(discovery: Discovery, limit_sessions: int = 20) -> Dict[str, Any]:
    claude_home = Path(discovery.claude_home)
    projects_dir = Path(discovery.claude_projects_dir)
    sessions_dir = Path(discovery.claude_sessions_dir)
    cc_db = Path(discovery.cc_switch_db)
    cc_settings = Path(discovery.cc_switch_settings)

    checks = {
        "claude_bin_found": bool(discovery.claude_bin and Path(discovery.claude_bin).exists()),
        "claude_version": discovery.claude_version,
        "claude_home_exists": claude_home.exists(),
        "claude_projects_dir_exists": projects_dir.exists(),
        "claude_sessions_dir_exists": sessions_dir.exists(),
        "claude_global_memory_exists": Path(discovery.claude_global_memory).exists(),
        "cc_switch_db_exists": cc_db.exists(),
        "cc_switch_settings_exists": cc_settings.exists(),
    }

    try:
        session_summaries = scan_sessions(projects_dir, sessions_dir, limit=limit_sessions)
        checks["session_scan_ok"] = True
    except Exception as exc:
        session_summaries = []
        checks["session_scan_ok"] = False
        checks["session_scan_error"] = str(exc)

    try:
        cc_info = inspect_ccswitch(cc_db)
        checks["cc_switch_inspect_ok"] = True
    except Exception as exc:
        cc_info = {"error": str(exc), "path": str(cc_db)}
        checks["cc_switch_inspect_ok"] = False

    status = "ok"
    if not checks["claude_home_exists"] or not checks["cc_switch_db_exists"]:
        status = "warning"
    if checks.get("cc_switch_inspect_ok") is False:
        status = "danger"

    return {
        "status": status,
        "discovery": discovery.to_dict(),
        "checks": checks,
        "ccSwitch": cc_info,
        "recentSessions": [s.to_dict() for s in session_summaries],
    }
