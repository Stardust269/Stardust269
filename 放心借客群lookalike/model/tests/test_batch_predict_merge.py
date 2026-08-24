"""batch_predict_merge 合并逻辑单测。"""

from __future__ import annotations

import sys
from pathlib import Path

import pandas as pd
import pytest

MODEL_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(MODEL_ROOT / "scripts"))

from batch_predict_merge import merge_and_rank, merge_key_columns  # noqa: E402


def test_merge_and_rank_orders_by_score() -> None:
    p1 = pd.DataFrame(
        {
            "unique_id": ["a", "b"],
            "dt_zx": ["20240701", "20240701"],
            "lookalike_score": [0.2, 0.9],
        }
    )
    p2 = pd.DataFrame(
        {
            "unique_id": ["c"],
            "dt_zx": ["20240702"],
            "lookalike_score": [0.5],
        }
    )
    merged = merge_and_rank([p1, p2])
    assert list(merged["unique_id"]) == ["b", "c", "a"]
    assert list(merged["global_rank"]) == [1, 2, 3]


def test_merge_rejects_duplicate_keys() -> None:
    p1 = pd.DataFrame({"unique_id": ["a"], "lookalike_score": [0.1]})
    p2 = pd.DataFrame({"unique_id": ["a"], "lookalike_score": [0.2]})
    with pytest.raises(ValueError, match="重复主键"):
        merge_and_rank([p1, p2])


def test_merge_key_columns_prefers_unique_id_and_dt_zx() -> None:
    df = pd.DataFrame({"unique_id": ["a"], "dt_zx": [1], "lookalike_score": [0.1]})
    assert merge_key_columns(df) == ["unique_id", "dt_zx"]
