"""score_percentile_band_table 单测。"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from metrics import score_percentile_band_table  # noqa: E402


def test_unlabeled_scores_have_zero_seeds() -> None:
    n = 10_000
    scores = np.linspace(0, 1, n)
    df = score_percentile_band_table(scores)
    body = df[df["score百分位"] != "总计"]
    assert (body["种子用户数"] == 0).all()
    p99 = body.loc[body["score百分位"] == "p99", "总数"].iloc[0]
    assert int(p99) == max(int(round(n * 0.01)), 1)
