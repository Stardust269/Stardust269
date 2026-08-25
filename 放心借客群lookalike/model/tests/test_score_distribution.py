"""score_distribution / score_percentile_band 单测。"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
import pytest

MODEL_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(MODEL_ROOT / "scripts"))
sys.path.insert(0, str(MODEL_ROOT / "src"))

from metrics import score_percentile_band_table  # noqa: E402
from score_distribution import score_histogram, summarize_scores  # noqa: E402


def test_summarize_scores_basic() -> None:
    scores = np.linspace(0.01, 0.99, 1000, dtype=np.float32)
    s = summarize_scores(scores)
    assert s["n"] == 1000
    assert 0.0 <= s["min"] < s["max"] <= 1.0
    assert "p50" in s["percentiles"]


def test_histogram_sums_to_one() -> None:
    rng = np.random.RandomState(0)
    scores = rng.rand(5000).astype(np.float32)
    hist = score_histogram(scores, bins=10)
    assert abs(hist["ratio"].sum() - 1.0) < 1e-6


def test_score_percentile_band_table_order_and_slices() -> None:
    scores = np.arange(100, dtype=np.float32) / 100.0
    bands = score_percentile_band_table(scores)
    body = bands[bands["score百分位"] != "总计"]
    assert body.iloc[0]["score百分位"] == "p99"
    assert int(body.iloc[0]["总数"]) == 1
    assert int(body.iloc[0]["累计总数"]) == 1
    assert body.iloc[1]["score百分位"] == "p98"
    assert int(body.iloc[1]["总数"]) == 1
    assert int(body.iloc[1]["累计总数"]) == 2
    assert bands.iloc[-1]["score百分位"] == "总计"
    assert int(bands.iloc[-1]["总数"]) == 100
