from __future__ import annotations

from pathlib import Path
from typing import Dict, Optional

from .backup import create_backup


START = "<!-- cc-mimo-rescue:start -->"
END = "<!-- cc-mimo-rescue:end -->"

def build_memory_block(image_model: str = "mimo-v2.5", helper_model: str = "haiku") -> str:
    helper = helper_model.lower()
    return f"""{START}
When the user asks about images, screenshots, charts, PDFs containing images, or local image paths, do not use Read on binary/image files and do not send image/base64 content to the main MiMo Pro route.

Reason: direct image/binary reads can make the main conversation freeze or become unresponsive because large base64/media payloads get injected into the transcript.

Use a Claude subagent first (`subagent_type: "claude"`, `model: "{helper}"`). CC Switch should route that image helper to `{image_model}`. The helper should convert the image into text using local tools, OCR, or image analysis, then return only the text summary to the main conversation.
{END}
"""


MEMORY_BLOCK = build_memory_block()


def preview_memory(path: Path, image_model: str = "mimo-v2.5", helper_model: str = "haiku") -> Dict[str, object]:
    exists = path.exists()
    text = path.read_text(encoding="utf-8") if exists else ""
    block = build_memory_block(image_model, helper_model)
    current_block = _extract_managed_block(text)
    has_block = current_block is not None
    block_at_end = bool(current_block and text.rstrip().endswith(current_block.rstrip()))
    return {
        "path": str(path),
        "exists": exists,
        "hasManagedBlock": has_block,
        "changed": current_block != block or not block_at_end,
        "block": block,
        "helperModel": helper_model,
        "imageModel": image_model,
        "blockAtEnd": block_at_end,
    }


def apply_memory(
    path: Path,
    yes: bool = False,
    image_model: str = "mimo-v2.5",
    helper_model: str = "haiku",
) -> Dict[str, object]:
    preview = preview_memory(path, image_model, helper_model)
    if not yes:
        return {**preview, "applied": False, "message": "dry run; pass --yes to write"}
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        backup_dir = create_backup(path, "memory-config", {"preview": preview})
        text = path.read_text(encoding="utf-8")
    else:
        backup_dir = None
        text = ""
    if not preview["changed"]:
        return {**preview, "applied": False, "message": "managed block already up to date"}
    cleaned = _remove_managed_block(text).rstrip()
    sep = "\n\n" if cleaned else ""
    path.write_text(cleaned + sep + str(preview["block"]).rstrip() + "\n", encoding="utf-8")
    return {**preview, "applied": True, "backup": str(backup_dir) if backup_dir else None}


def reset_memory(path: Path, yes: bool = False) -> Dict[str, object]:
    exists = path.exists()
    text = path.read_text(encoding="utf-8") if exists else ""
    has_block = _extract_managed_block(text) is not None
    preview: Dict[str, object] = {
        "path": str(path),
        "exists": exists,
        "hasManagedBlock": has_block,
        "changed": has_block,
        "block": "",
    }
    if not yes:
        return {**preview, "applied": False, "message": "dry run; pass --yes to write"}
    if not exists or not has_block:
        return {**preview, "applied": False, "message": "managed block not found"}
    backup_dir = create_backup(path, "memory-reset", {"preview": preview})
    path.write_text(_remove_managed_block(text).rstrip() + "\n", encoding="utf-8")
    return {**preview, "applied": True, "backup": str(backup_dir)}


def _extract_managed_block(text: str) -> Optional[str]:
    start = text.find(START)
    if start < 0:
        return None
    end = text.find(END, start)
    if end < 0:
        return None
    return text[start : end + len(END)]


def _remove_managed_block(text: str) -> str:
    block = _extract_managed_block(text)
    if not block:
        return text
    return text.replace(block, "", 1)
