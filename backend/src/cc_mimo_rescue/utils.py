from __future__ import annotations

import hashlib
import json
import os
import re
from pathlib import Path
from typing import Any, Dict


SENSITIVE_KEY_RE = re.compile(r"(token|key|secret|password|authorization|auth)", re.I)
BASE64_RE = re.compile(r"^[A-Za-z0-9+/=\s]+$")


def json_dump(data: Any) -> str:
    return json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True)


def print_json(data: Any) -> None:
    print(json_dump(data))


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def ensure_dir(path: Path) -> Path:
    path.mkdir(parents=True, exist_ok=True)
    return path


def now_stamp() -> str:
    from datetime import datetime

    return datetime.now().strftime("%Y%m%d-%H%M%S")


def xdg_config_home() -> Path:
    return Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")).expanduser()


def xdg_data_home() -> Path:
    return Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local" / "share")).expanduser()


def app_config_dir() -> Path:
    return xdg_config_home() / "cc-mimo-rescue"


def app_data_dir() -> Path:
    return xdg_data_home() / "cc-mimo-rescue"


def app_backup_dir() -> Path:
    return app_data_dir() / "backups"


def app_audit_dir() -> Path:
    return app_data_dir() / "audit"


def redact(value: Any, key: str = "") -> Any:
    if SENSITIVE_KEY_RE.search(key):
        return "[REDACTED]"
    if isinstance(value, dict):
        return {k: redact(v, k) for k, v in value.items()}
    if isinstance(value, list):
        return [redact(v, key) for v in value]
    if isinstance(value, str):
        if len(value) > 24 and re.search(r"(sk-|tp-|eyJ|Bearer\s+)", value):
            return "[REDACTED]"
    return value


def is_base64_risk(text: str, min_len: int = 4096) -> bool:
    compact = "".join(text.split())
    if len(compact) < min_len:
        return False
    if text.startswith("data:image/") or text.startswith("data:application/pdf"):
        return True
    if not BASE64_RE.match(text):
        return False
    unique = len(set(compact))
    return unique > 20 and len(compact) % 4 in (0, 2, 3)


def safe_preview(text: str, limit: int = 180) -> str:
    one_line = " ".join(text.replace("\x00", "").split())
    if len(one_line) <= limit:
        return one_line
    return one_line[:limit] + "..."


def read_json_file(path: Path) -> Dict[str, Any]:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)
