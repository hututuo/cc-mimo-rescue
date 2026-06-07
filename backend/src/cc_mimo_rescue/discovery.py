from __future__ import annotations

import os
import shutil
import subprocess
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Dict, Optional

from .utils import app_config_dir


@dataclass
class Discovery:
    claude_bin: Optional[str]
    claude_version: Optional[str]
    claude_home: str
    claude_projects_dir: str
    claude_sessions_dir: str
    claude_global_memory: str
    cc_switch_home: str
    cc_switch_db: str
    cc_switch_settings: str
    config_path: str

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


def _version(bin_path: Optional[str]) -> Optional[str]:
    if not bin_path:
        return None
    try:
        proc = subprocess.run(
            [bin_path, "--version"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=5,
        )
    except Exception:
        return None
    return proc.stdout.strip() or None


def discover() -> Discovery:
    claude_bin = shutil.which("claude")
    if not claude_bin:
        for candidate in (
            Path.home() / ".local" / "bin" / "claude",
            Path("/opt/homebrew/bin/claude"),
            Path("/usr/local/bin/claude"),
        ):
            if candidate.exists():
                claude_bin = str(candidate)
                break

    claude_home = Path(os.environ.get("CLAUDE_CONFIG_DIR", Path.home() / ".claude")).expanduser()
    cc_home = Path.home() / ".cc-switch"

    discovered = Discovery(
        claude_bin=claude_bin,
        claude_version=_version(claude_bin),
        claude_home=str(claude_home),
        claude_projects_dir=str(claude_home / "projects"),
        claude_sessions_dir=str(claude_home / "sessions"),
        claude_global_memory=str(claude_home / "CLAUDE.md"),
        cc_switch_home=str(cc_home),
        cc_switch_db=str(cc_home / "cc-switch.db"),
        cc_switch_settings=str(cc_home / "settings.json"),
        config_path=str(app_config_dir() / "config.toml"),
    )
    return apply_saved_config(discovered)


def apply_saved_config(discovery: Discovery) -> Discovery:
    path = Path(discovery.config_path)
    if not path.exists():
        return discovery
    try:
        config = parse_simple_toml(path.read_text(encoding="utf-8"))
    except Exception:
        return discovery

    claude = config.get("claude", {})
    cc_switch = config.get("cc_switch", {})

    return Discovery(
        claude_bin=_blank_to_none(claude.get("bin", discovery.claude_bin)),
        claude_version=_version(_blank_to_none(claude.get("bin", discovery.claude_bin))),
        claude_home=str(Path(claude.get("home", discovery.claude_home)).expanduser()),
        claude_projects_dir=str(Path(claude.get("projects_dir", discovery.claude_projects_dir)).expanduser()),
        claude_sessions_dir=str(Path(claude.get("sessions_dir", discovery.claude_sessions_dir)).expanduser()),
        claude_global_memory=str(Path(claude.get("global_memory", discovery.claude_global_memory)).expanduser()),
        cc_switch_home=str(Path(cc_switch.get("home", discovery.cc_switch_home)).expanduser()),
        cc_switch_db=str(Path(cc_switch.get("db", discovery.cc_switch_db)).expanduser()),
        cc_switch_settings=str(Path(cc_switch.get("settings", discovery.cc_switch_settings)).expanduser()),
        config_path=discovery.config_path,
    )


def write_config(discovery: Discovery) -> Path:
    config_dir = app_config_dir()
    config_dir.mkdir(parents=True, exist_ok=True)
    path = config_dir / "config.toml"
    text = f"""[claude]
bin = {toml_str(discovery.claude_bin or "")}
home = {toml_str(discovery.claude_home)}
projects_dir = {toml_str(discovery.claude_projects_dir)}
sessions_dir = {toml_str(discovery.claude_sessions_dir)}
global_memory = {toml_str(discovery.claude_global_memory)}

[cc_switch]
home = {toml_str(discovery.cc_switch_home)}
db = {toml_str(discovery.cc_switch_db)}
settings = {toml_str(discovery.cc_switch_settings)}

[models]
main = "mimo-v2.5-pro[1m]"
image_route = "mimo-v2.5"
haiku_aliases = ["claude-haiku-4-5", "claude-3-5-haiku-latest", "haiku"]

[behavior]
backup_dir = {toml_str(str(Path.home() / ".local" / "share" / "cc-mimo-rescue" / "backups"))}
default_clean_mode = "replace-media-with-placeholder"
dry_run_by_default = true
"""
    path.write_text(text, encoding="utf-8")
    return path


def toml_str(value: str) -> str:
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def parse_simple_toml(text: str) -> Dict[str, Dict[str, Any]]:
    """Parse the small TOML subset written by write_config.

    This avoids a dependency on tomllib for macOS Python 3.9.
    """

    data: Dict[str, Dict[str, Any]] = {}
    section: Optional[str] = None
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1].strip()
            data.setdefault(section, {})
            continue
        if section and "=" in line:
            key, value = line.split("=", 1)
            data[section][key.strip()] = parse_simple_value(value.strip())
    return data


def parse_simple_value(value: str) -> Any:
    if value in ("true", "false"):
        return value == "true"
    if value.startswith('"') and value.endswith('"'):
        inner = value[1:-1]
        return inner.replace('\\"', '"').replace("\\\\", "\\")
    if value.startswith("[") and value.endswith("]"):
        items = []
        body = value[1:-1].strip()
        if not body:
            return items
        for item in body.split(","):
            items.append(parse_simple_value(item.strip()))
        return items
    return value


def _blank_to_none(value: Any) -> Optional[str]:
    if value is None:
        return None
    text = str(value)
    return text or None
