"""score_percentile_band_table 单测。"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from metrics import score_percentile_band_table  # noqa: E402


def test_band_slice_and_cumulative_stats() -> None:
    scores = np.arange(100, dtype=np.float64) / 100.0
    df = score_percentile_band_table(scores)
    p99 = df.loc[df["score百分位"] == "p99"].iloc[0]
    p98 = df.loc[df["score百分位"] == "p98"].iloc[0]

    assert int(p99["总数"]) == 1
    assert p99["分数_max"] == pytest.approx(0.99)
    assert p99["累计分数_max"] == pytest.approx(0.99)
    assert p99["累计分数_min"] == pytest.approx(0.99)

    assert int(p98["总数"]) == 1
    assert p98["分数_max"] == pytest.approx(0.98)
    assert p98["累计分数_max"] == pytest.approx(0.99)
    assert p98["累计分数_min"] == pytest.approx(0.98)
    assert int(p98["累计总数"]) == 2


def test_large_n_p99_count() -> None:
    n = 10_000
    scores = np.linspace(0, 1, n)
    df = score_percentile_band_table(scores)
    p99 = df.loc[df["score百分位"] == "p99", "总数"].iloc[0]
    assert int(p99) == max(int(round(n * 0.01)), 1)
