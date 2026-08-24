"""固定绝对人数 TGI 分档回归测试。"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from metrics import PRE_TGI_TEST_BAND_SIZES, tgi_percentile_table_fixed_bands  # noqa: E402


def test_fixed_band_sizes_match_colleague_pattern():
    assert PRE_TGI_TEST_BAND_SIZES[99] == 46731
    assert PRE_TGI_TEST_BAND_SIZES[98] == 46732
    assert PRE_TGI_TEST_BAND_SIZES[25] == 46732
    assert len(PRE_TGI_TEST_BAND_SIZES) == 23


def test_fixed_bands_use_absolute_counts_not_ratio():
    rng = np.random.default_rng(0)
    n = 50_000
    y = rng.integers(0, 2, size=n)
    score = rng.random(n)
    df = tgi_percentile_table_fixed_bands(y, score)
    body = df[df["tgi百分位"] != "总计"]
    p99 = body.loc[body["tgi百分位"] == "p99", "总数"].iloc[0]
    p98 = body.loc[body["tgi百分位"] == "p98", "总数"].iloc[0]
    assert int(p99) == 46731
    assert int(p98) == 46732


def test_p00_is_remainder():
    rng = np.random.default_rng(1)
    n = 200_000
    y = rng.integers(0, 2, size=n)
    score = rng.random(n)
    df = tgi_percentile_table_fixed_bands(y, score)
    body = df[df["tgi百分位"] != "总计"]
    p00 = body.loc[body["tgi百分位"] == "p00", "总数"].iloc[0]
    top_sum = int(body.loc[body["tgi百分位"] != "p00", "总数"].sum())
    assert int(p00) == n - top_sum
