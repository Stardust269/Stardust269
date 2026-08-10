from __future__ import annotations

from pathlib import Path

import yaml


def load_config(path: Path) -> dict:
    with Path(path).open("r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def resolve_path(path_str: str, config_path: Path) -> Path:
    p = Path(path_str)
    if p.is_absolute():
        return p
    return (config_path.parent / p).resolve()
