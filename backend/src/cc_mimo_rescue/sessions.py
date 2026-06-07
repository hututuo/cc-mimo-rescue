from __future__ import annotations

import json
import os
import re
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple

from .backup import create_backup
from .utils import is_base64_risk, safe_preview, sha256_file


MEDIA_TYPES = {"image", "image_url", "media", "document"}
IMAGE_PATH_RE = re.compile(r"(?i)(/[^\n\r\t\"']+\.(?:png|jpe?g|gif|webp|tiff?|bmp|pdf))")


@dataclass
class RiskHit:
    line: int
    kind: str
    bytes: int
    preview: str
    uuid: Optional[str] = None


@dataclass
class SessionSummary:
    sessionId: str
    projectKey: str
    transcriptPath: str
    projectPath: Optional[str] = None
    activeSessionPath: Optional[str] = None
    startedAt: Optional[str] = None
    updatedAt: Optional[str] = None
    messageCount: int = 0
    modelCounts: Dict[str, int] = field(default_factory=dict)
    toolUseCounts: Dict[str, int] = field(default_factory=dict)
    mediaBlockCount: int = 0
    base64RiskCount: int = 0
    imagePathMentionCount: int = 0
    estimatedBytes: int = 0
    risk: str = "ok"
    riskReasons: List[str] = field(default_factory=list)

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


def project_key_to_path(project_key: str) -> Optional[str]:
    if not project_key.startswith("-"):
        return None
    raw = project_key[1:]
    if not raw:
        return None
    return "/" + raw.replace("-", "/")


def find_transcripts(projects_dir: Path) -> Iterable[Path]:
    if not projects_dir.exists():
        return []
    return sorted(projects_dir.glob("*/*.jsonl"), key=lambda p: p.stat().st_mtime, reverse=True)


def load_active_sessions(sessions_dir: Path) -> Dict[str, Dict[str, Any]]:
    out: Dict[str, Dict[str, Any]] = {}
    if not sessions_dir.exists():
        return out
    for path in sessions_dir.glob("*.json"):
        try:
            obj = json.loads(path.read_text(encoding="utf-8"))
        except Exception:
            continue
        sid = obj.get("sessionId")
        if sid:
            obj["_path"] = str(path)
            out[sid] = obj
    return out


def scan_sessions(
    projects_dir: Path,
    sessions_dir: Path,
    project_filter: Optional[str] = None,
    limit: Optional[int] = None,
    risk_filter: Optional[str] = None,
) -> List[SessionSummary]:
    active = load_active_sessions(sessions_dir)
    summaries: List[SessionSummary] = []
    for transcript in find_transcripts(projects_dir):
        if project_filter and project_filter not in str(transcript):
            continue
        summary = scan_transcript(transcript, active)
        if risk_filter and summary.risk != risk_filter:
            continue
        summaries.append(summary)
        if limit is not None and len(summaries) >= limit:
            break
    return summaries


def count_transcripts(projects_dir: Path, project_filter: Optional[str] = None) -> int:
    total = 0
    for transcript in find_transcripts(projects_dir):
        if project_filter and project_filter not in str(transcript):
            continue
        total += 1
    return total


def scan_transcript(transcript: Path, active: Optional[Dict[str, Dict[str, Any]]] = None) -> SessionSummary:
    project_key = transcript.parent.name
    session_id = transcript.stem
    active_obj = (active or {}).get(session_id, {})
    st = transcript.stat()
    summary = SessionSummary(
        sessionId=session_id,
        projectKey=project_key,
        projectPath=active_obj.get("cwd"),
        transcriptPath=str(transcript),
        activeSessionPath=active_obj.get("_path"),
        updatedAt=_mtime_iso(st.st_mtime),
        estimatedBytes=st.st_size,
    )

    for line_no, line, obj in iter_jsonl(transcript):
        if obj is None:
            continue
        if not summary.projectPath and isinstance(obj.get("cwd"), str):
            summary.projectPath = obj.get("cwd")
        if not summary.startedAt and isinstance(obj.get("timestamp"), str):
            summary.startedAt = obj.get("timestamp")
        summary.messageCount += 1
        msg = obj.get("message") if isinstance(obj, dict) else None
        if isinstance(msg, dict):
            model = msg.get("model")
            if model:
                summary.modelCounts[model] = summary.modelCounts.get(model, 0) + 1
            content = msg.get("content")
            media, b64, image_paths, tools = inspect_content(content)
            summary.mediaBlockCount += media
            summary.base64RiskCount += b64
            summary.imagePathMentionCount += image_paths
            for name in tools:
                summary.toolUseCounts[name] = summary.toolUseCounts.get(name, 0) + 1
        else:
            media, b64, image_paths, tools = inspect_content(obj)
            summary.mediaBlockCount += media
            summary.base64RiskCount += b64
            summary.imagePathMentionCount += image_paths
            for name in tools:
                summary.toolUseCounts[name] = summary.toolUseCounts.get(name, 0) + 1

    reasons: List[str] = []
    if summary.mediaBlockCount:
        reasons.append(f"media blocks: {summary.mediaBlockCount}")
    if summary.base64RiskCount:
        reasons.append(f"base64 risks: {summary.base64RiskCount}")
    if summary.imagePathMentionCount:
        reasons.append(f"image path mentions: {summary.imagePathMentionCount}")
    if summary.estimatedBytes > 5 * 1024 * 1024:
        reasons.append(f"large transcript: {summary.estimatedBytes} bytes")
    summary.riskReasons = reasons
    if summary.base64RiskCount or summary.mediaBlockCount > 5 or summary.estimatedBytes > 15 * 1024 * 1024:
        summary.risk = "danger"
    elif summary.mediaBlockCount or summary.imagePathMentionCount or summary.estimatedBytes > 5 * 1024 * 1024:
        summary.risk = "warning"
    if not summary.projectPath:
        summary.projectPath = project_key_to_path(project_key)
    return summary


def iter_jsonl(path: Path) -> Iterable[Tuple[int, str, Optional[Dict[str, Any]]]]:
    with path.open("r", encoding="utf-8", errors="replace") as f:
        for i, line in enumerate(f, 1):
            stripped = line.rstrip("\n")
            try:
                obj = json.loads(stripped)
            except Exception:
                obj = None
            yield i, stripped, obj


def inspect_content(value: Any) -> Tuple[int, int, int, List[str]]:
    media = 0
    b64 = 0
    image_paths = 0
    tools: List[str] = []

    def walk(v: Any, key: str = "") -> None:
        nonlocal media, b64, image_paths
        if isinstance(v, dict):
            t = v.get("type")
            if t in MEDIA_TYPES:
                media += 1
            if t == "tool_use":
                name = v.get("name")
                if isinstance(name, str):
                    tools.append(name)
            for k, child in v.items():
                walk(child, k)
        elif isinstance(v, list):
            for child in v:
                walk(child, key)
        elif isinstance(v, str):
            if is_base64_risk(v):
                b64 += 1
            image_paths += len(IMAGE_PATH_RE.findall(v))

    walk(value)
    return media, b64, image_paths, tools


def collect_risk_hits(transcript: Path) -> List[RiskHit]:
    hits: List[RiskHit] = []
    for line_no, line, obj in iter_jsonl(transcript):
        if obj is None:
            continue
        for kind, size, preview in find_risky_values(obj):
            hits.append(RiskHit(line=line_no, kind=kind, bytes=size, preview=preview, uuid=obj.get("uuid")))
    return hits


def find_risky_values(value: Any) -> Iterable[Tuple[str, int, str]]:
    if isinstance(value, dict):
        t = value.get("type")
        if t in MEDIA_TYPES:
            yield ("media-block", len(json.dumps(value, ensure_ascii=False)), safe_preview(json.dumps(value, ensure_ascii=False)))
        for child in value.values():
            yield from find_risky_values(child)
    elif isinstance(value, list):
        for child in value:
            yield from find_risky_values(child)
    elif isinstance(value, str):
        if is_base64_risk(value):
            yield ("base64", len(value), safe_preview(value))


def preview_clean(transcript: Path, mode: str = "replace-media-with-placeholder") -> Dict[str, Any]:
    changes = []
    for line_no, line, obj in iter_jsonl(transcript):
        if obj is None:
            continue
        cleaned, changed, line_changes = clean_obj(obj, mode)
        if changed:
            changes.extend(
                {
                    "line": line_no,
                    "uuid": obj.get("uuid"),
                    "kind": c["kind"],
                    "beforeBytes": c["beforeBytes"],
                    "afterBytes": c["afterBytes"],
                    "previewBefore": c["previewBefore"],
                    "previewAfter": c["previewAfter"],
                }
                for c in line_changes
            )
    return {
        "transcriptPath": str(transcript),
        "mode": mode,
        "changes": changes,
        "changeCount": len(changes),
        "backupRequired": True,
    }


def apply_clean(transcript: Path, mode: str, yes: bool = False) -> Dict[str, Any]:
    preview = preview_clean(transcript, mode)
    if not yes:
        return {**preview, "applied": False, "message": "dry run; pass --yes to write"}
    backup_dir = create_backup(transcript, "session-clean", {"mode": mode, "preview": preview})
    tmp = transcript.with_suffix(transcript.suffix + ".cc-mimo-rescue.tmp")
    changed_lines = 0
    with transcript.open("r", encoding="utf-8", errors="replace") as src, tmp.open("w", encoding="utf-8") as dst:
        for line in src:
            stripped = line.rstrip("\n")
            try:
                obj = json.loads(stripped)
            except Exception:
                dst.write(line)
                continue
            cleaned, changed, _ = clean_obj(obj, mode)
            if changed:
                changed_lines += 1
                dst.write(json.dumps(cleaned, ensure_ascii=False, separators=(",", ":")) + "\n")
            else:
                dst.write(line)
    os.replace(tmp, transcript)
    return {
        **preview,
        "applied": True,
        "changedLines": changed_lines,
        "backup": str(backup_dir),
        "newSha256": sha256_file(transcript),
    }


def clean_obj(value: Any, mode: str) -> Tuple[Any, bool, List[Dict[str, Any]]]:
    changes: List[Dict[str, Any]] = []

    def clean(v: Any) -> Tuple[Any, bool]:
        if isinstance(v, dict):
            t = v.get("type")
            if t in MEDIA_TYPES:
                before = json.dumps(v, ensure_ascii=False)
                if mode == "strip-media-blocks":
                    after: Any = None
                else:
                    after = {
                        "type": "text",
                        "text": f"[cc-mimo-rescue removed media block: original type={t}, bytes={len(before)}]",
                    }
                changes.append(
                    {
                        "kind": "media-block",
                        "beforeBytes": len(before),
                        "afterBytes": 0 if after is None else len(json.dumps(after, ensure_ascii=False)),
                        "previewBefore": safe_preview(before),
                        "previewAfter": "" if after is None else safe_preview(json.dumps(after, ensure_ascii=False)),
                    }
                )
                return after, True
            out: Dict[str, Any] = {}
            changed = False
            for k, child in v.items():
                new_child, child_changed = clean(child)
                if child_changed:
                    changed = True
                if new_child is not None:
                    out[k] = new_child
            return out, changed
        if isinstance(v, list):
            out_list: List[Any] = []
            changed = False
            for child in v:
                new_child, child_changed = clean(child)
                if child_changed:
                    changed = True
                if new_child is not None:
                    out_list.append(new_child)
            return out_list, changed
        if isinstance(v, str) and is_base64_risk(v):
            after = f"[cc-mimo-rescue removed base64-like content: bytes={len(v)}]"
            changes.append(
                {
                    "kind": "base64",
                    "beforeBytes": len(v),
                    "afterBytes": len(after),
                    "previewBefore": safe_preview(v),
                    "previewAfter": after,
                }
            )
            return after, True
        return v, False

    cleaned, changed = clean(value)
    return cleaned, changed, changes


def _mtime_iso(ts: float) -> str:
    from datetime import datetime

    return datetime.fromtimestamp(ts).isoformat(timespec="seconds")
