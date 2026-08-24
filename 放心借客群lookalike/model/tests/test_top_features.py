"""top_features 工具函数单测。"""

from __future__ import annotations

import sys
from pathlib import Path

import pandas as pd

MODEL_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(MODEL_ROOT / "src"))

from top_features import load_top_feature_names, save_feature_name_list  # noqa: E402


def test_load_top_feature_names_with_sidecar(tmp_path: Path) -> None:
    imp = tmp_path / "model_feature_importance.csv"
    pd.DataFrame(
        {
            "feature": ["Column_0", "Column_1", "risk_score_a"],
            "gain": [100.0, 50.0, 10.0],
        }
    ).to_csv(imp, index=False)

    sidecar = tmp_path / "model_features.json"
    sidecar.write_text('["feat_a", "feat_b", "risk_score_a"]', encoding="utf-8")
    model = tmp_path / "model.txt"
    model.write_text("", encoding="utf-8")

    names = load_top_feature_names(imp, top=2, model_path=model, features_path=sidecar)
    assert names == ["feat_a", "feat_b"]


def test_save_feature_name_list(tmp_path: Path) -> None:
    out = tmp_path / "top.txt"
    save_feature_name_list(["a", "b", "c"], out)
    assert out.read_text(encoding="utf-8").strip().splitlines() == ["a", "b", "c"]
