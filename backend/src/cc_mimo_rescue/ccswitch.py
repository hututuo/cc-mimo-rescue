from __future__ import annotations

import json
import shutil
import sqlite3
from pathlib import Path
from typing import Any, Dict, List, Optional

from .backup import create_backup
from .utils import redact


MODEL_ENV_KEYS = [
    "ANTHROPIC_DEFAULT_HAIKU_MODEL",
    "ANTHROPIC_DEFAULT_OPUS_MODEL",
    "ANTHROPIC_DEFAULT_SONNET_MODEL",
    "ANTHROPIC_MODEL",
]

MODEL_KEY_BY_SLOT = {
    "haiku": "ANTHROPIC_DEFAULT_HAIKU_MODEL",
    "opus": "ANTHROPIC_DEFAULT_OPUS_MODEL",
    "sonnet": "ANTHROPIC_DEFAULT_SONNET_MODEL",
    "main": "ANTHROPIC_MODEL",
}


def inspect(db_path: Path) -> Dict[str, Any]:
    if not db_path.exists():
        return {"exists": False, "path": str(db_path)}
    rows = _provider_rows(db_path)
    claude_rows = [r for r in rows if r.get("app_type") == "claude"]
    current = [r for r in claude_rows if r.get("is_current")]
    return {
        "exists": True,
        "path": str(db_path),
        "integrity": integrity(db_path),
        "providers": [_redacted_provider(r) for r in claude_rows],
        "currentProviders": [_redacted_provider(r) for r in current],
    }


def preview_configure(
    db_path: Path,
    image_model: str,
    main_model: str,
    model_overrides: Optional[Dict[str, str]] = None,
) -> Dict[str, Any]:
    row = _select_current_claude_provider(db_path)
    before = json.loads(row["settings_config"])
    after = patch_settings_config(before, image_model, main_model, model_overrides)
    return {
        "provider": {
            "id": row["id"],
            "name": row["name"],
            "app_type": row["app_type"],
        },
        "before": _extract_model_env(before),
        "after": _extract_model_env(after),
        "changed": _extract_model_env(before) != _extract_model_env(after),
    }


def apply_configure(
    db_path: Path,
    settings_path: Optional[Path],
    image_model: str,
    main_model: str,
    yes: bool,
    model_overrides: Optional[Dict[str, str]] = None,
) -> Dict[str, Any]:
    preview = preview_configure(db_path, image_model, main_model, model_overrides)
    if not yes:
        return {**preview, "applied": False, "message": "dry run; pass --yes to write"}
    if not preview.get("changed"):
        return {**preview, "applied": False, "message": "already configured; no write needed"}
    backup_dir = create_backup(db_path, "ccswitch-config", {"preview": preview})
    if settings_path and settings_path.exists():
        shutil.copy2(settings_path, backup_dir / "settings.json")
    row = _select_current_claude_provider(db_path)
    config = json.loads(row["settings_config"])
    patched = patch_settings_config(config, image_model, main_model, model_overrides)
    with sqlite3.connect(str(db_path)) as conn:
        conn.execute("begin")
        conn.execute(
            "update providers set settings_config=? where id=? and app_type=?",
            (json.dumps(patched, ensure_ascii=False, separators=(",", ":")), row["id"], row["app_type"]),
        )
        conn.commit()
    return {**preview, "applied": True, "backup": str(backup_dir), "integrity": integrity(db_path)}


def patch_settings_config(
    config: Dict[str, Any],
    image_model: str,
    main_model: str,
    model_overrides: Optional[Dict[str, str]] = None,
) -> Dict[str, Any]:
    patched = json.loads(json.dumps(config))
    env = patched.setdefault("env", {})
    if model_overrides:
        for key, value in model_overrides.items():
            if key not in MODEL_ENV_KEYS:
                raise ValueError(f"unsupported model env key: {key}")
            if value:
                env[key] = value
    else:
        env["ANTHROPIC_DEFAULT_HAIKU_MODEL"] = image_model
        env["ANTHROPIC_DEFAULT_OPUS_MODEL"] = main_model
        env["ANTHROPIC_DEFAULT_SONNET_MODEL"] = main_model
        env["ANTHROPIC_MODEL"] = main_model
    return patched


def integrity(db_path: Path) -> str:
    try:
        with sqlite3.connect(str(db_path)) as conn:
            row = conn.execute("pragma integrity_check").fetchone()
            return row[0] if row else "unknown"
    except Exception as exc:
        return f"error: {exc}"


def _provider_rows(db_path: Path) -> List[Dict[str, Any]]:
    with sqlite3.connect(str(db_path)) as conn:
        conn.row_factory = sqlite3.Row
        rows = conn.execute(
            "select id, app_type, name, settings_config, is_current from providers where app_type='claude' order by is_current desc, name"
        ).fetchall()
    return [dict(r) for r in rows]


def _select_current_claude_provider(db_path: Path) -> Dict[str, Any]:
    rows = [r for r in _provider_rows(db_path) if r.get("app_type") == "claude" and r.get("is_current")]
    if len(rows) != 1:
        raise RuntimeError(f"expected exactly one current Claude provider, found {len(rows)}")
    return rows[0]


def _redacted_provider(row: Dict[str, Any]) -> Dict[str, Any]:
    out = {k: v for k, v in row.items() if k != "settings_config"}
    try:
        config = json.loads(row.get("settings_config") or "{}")
    except Exception:
        config = {}
    out["modelEnv"] = _extract_model_env(config)
    env = config.get("env") if isinstance(config, dict) else {}
    if isinstance(env, dict):
        out["baseUrl"] = env.get("ANTHROPIC_BASE_URL")
        out["hasAuthToken"] = any("TOKEN" in k or "KEY" in k for k in env)
    return out


def _extract_model_env(config: Dict[str, Any]) -> Dict[str, Any]:
    env = config.get("env") if isinstance(config, dict) else {}
    if not isinstance(env, dict):
        return {}
    return {k: env.get(k) for k in MODEL_ENV_KEYS if k in env}
