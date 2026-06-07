from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict

from .utils import app_audit_dir, ensure_dir, now_stamp, redact


def write_audit(event: Dict[str, Any]) -> Path:
    ensure_dir(app_audit_dir())
    day = now_stamp().split("-")[0]
    path = app_audit_dir() / f"{day}.jsonl"
    payload = dict(event)
    payload.setdefault("timestamp", now_stamp())
    payload = redact(payload)
    with path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(payload, ensure_ascii=False, sort_keys=True) + "\n")
    return path
