from __future__ import annotations

from pathlib import Path

import yaml

PACKAGE_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CONFIG_PATH = PACKAGE_ROOT / "config.yaml"


def load_config(path: Path | str | None = None) -> dict:
    cfg_path = Path(path) if path else DEFAULT_CONFIG_PATH
    with cfg_path.open("r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def resolve_path(relative: str, config_path: Path | None = None) -> Path:
    base = (config_path or DEFAULT_CONFIG_PATH).parent
    return (base / relative).resolve()
