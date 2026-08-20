from __future__ import annotations

import gc
from typing import Any


def release(*objs: Any) -> None:
    """显式释放大对象并触发垃圾回收。"""
    for obj in objs:
        del obj
    gc.collect()


def memory_cfg(training_cfg: dict) -> dict:
    defaults = {
        "use_float32": True,
        "release_dataframes": True,
        "release_train_matrix": True,
        "load_splits_separately": True,
        "lgb_free_raw_data": True,
        "skip_train_metrics": True,
        "valid_on_val_only": True,
        "max_bin": 127,
    }
    user = training_cfg.get("memory") or {}
    return {**defaults, **user}
