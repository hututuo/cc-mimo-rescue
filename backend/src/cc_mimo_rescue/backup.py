from __future__ import annotations

import json
import shutil
from pathlib import Path
from typing import Any, Dict, List

from .utils import app_backup_dir, ensure_dir, now_stamp, sha256_file


def create_backup(original: Path, topic: str, extra_manifest: Dict[str, Any]) -> Path:
    backup_id = f"{now_stamp()}_{topic}"
    target_dir = app_backup_dir() / backup_id
    suffix = 2
    while target_dir.exists():
        target_dir = app_backup_dir() / f"{backup_id}-{suffix}"
        suffix += 1
    ensure_dir(target_dir)
    backup_id = target_dir.name
    original_copy = target_dir / "original"
    shutil.copy2(original, original_copy)
    manifest = {
        "backup_id": backup_id,
        "original_path": str(original),
        "original_copy": str(original_copy),
        "original_sha256": sha256_file(original),
        "topic": topic,
        **extra_manifest,
    }
    (target_dir / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True),
        encoding="utf-8",
    )
    return target_dir


def create_session_full_backup(projects_dir: Path, sessions_dir: Path) -> Dict[str, Any]:
    backup_id = f"{now_stamp()}_sessions-full"
    target_dir = app_backup_dir() / backup_id
    suffix = 2
    while target_dir.exists():
        target_dir = app_backup_dir() / f"{backup_id}-{suffix}"
        suffix += 1
    ensure_dir(target_dir)
    backup_id = target_dir.name

    copied: List[Dict[str, Any]] = []
    missing: List[str] = []
    for name, source in (("projects", projects_dir), ("sessions", sessions_dir)):
        source = source.expanduser()
        if not source.exists():
            missing.append(str(source))
            continue
        destination = target_dir / name
        if source.is_dir():
            shutil.copytree(source, destination, symlinks=True)
        else:
            shutil.copy2(source, destination)
        copied.append({"name": name, "source": str(source), "copy": str(destination)})

    total_files, total_bytes = _count_files(target_dir)
    manifest = {
        "backup_id": backup_id,
        "topic": "sessions-full",
        "scope": "claude-session-records",
        "path": str(target_dir),
        "original_paths": [item["source"] for item in copied],
        "copied": copied,
        "missing": missing,
        "totalFiles": total_files,
        "totalBytes": total_bytes,
        "restorable": False,
        "privacy": "local-only; no network upload; no telemetry",
    }
    (target_dir / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True),
        encoding="utf-8",
    )
    return manifest


def list_backups() -> List[Dict[str, Any]]:
    root = app_backup_dir()
    if not root.exists():
        return []
    items: List[Dict[str, Any]] = []
    for d in sorted((p for p in root.iterdir() if p.is_dir()), reverse=True):
        manifest_path = d / "manifest.json"
        if manifest_path.exists():
            try:
                manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            except Exception:
                manifest = {"backup_id": d.name, "error": "manifest parse failed"}
        else:
            manifest = {"backup_id": d.name, "error": "manifest missing"}
        manifest["path"] = str(d)
        items.append(manifest)
    return items


def restore_backup(backup_id: str, apply: bool = False) -> Dict[str, Any]:
    if Path(backup_id).name != backup_id:
        raise ValueError(f"invalid backup id: {backup_id}")
    root = app_backup_dir().resolve()
    target_dir = (root / backup_id).resolve()
    if root not in target_dir.parents:
        raise ValueError(f"invalid backup id: {backup_id}")
    manifest_path = target_dir / "manifest.json"
    if not manifest_path.exists():
        raise FileNotFoundError(f"backup manifest not found: {backup_id}")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if "original_path" not in manifest:
        raise ValueError(f"backup is not a single-file restorable backup: {backup_id}")
    original_path = Path(manifest["original_path"])
    original_copy = Path(manifest["original_copy"])
    result = {
        "backup_id": backup_id,
        "restore_to": str(original_path),
        "source": str(original_copy),
        "applied": False,
    }
    if apply:
        shutil.copy2(original_copy, original_path)
        result["applied"] = True
    return result


def _count_files(path: Path) -> tuple[int, int]:
    files = 0
    total = 0
    for item in path.rglob("*"):
        if item.is_file() and not item.is_symlink():
            files += 1
            try:
                total += item.stat().st_size
            except OSError:
                pass
    return files, total
