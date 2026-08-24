"""score_distribution 工具单测。"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
import pytest

MODEL_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(MODEL_ROOT / "scripts"))
sys.path.insert(0, str(MODEL_ROOT / "src"))

from score_distribution import score_histogram, summarize_scores, top_band_table  # noqa: E402


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


def test_top_band_table() -> None:
    scores = np.arange(100, dtype=np.float32) / 100.0
    bands = top_band_table(scores)
    assert len(bands) == 24  # top 1~5% + 10~100% 步长 5%
    assert bands.iloc[0]["top_pct"] == "top_1%"
    assert bands.iloc[0]["count"] == 1
    assert bands.iloc[0]["score_max"] == pytest.approx(0.99)
    assert bands.iloc[-1]["top_pct"] == "top_100%"
    assert bands.iloc[-1]["count"] == 100
