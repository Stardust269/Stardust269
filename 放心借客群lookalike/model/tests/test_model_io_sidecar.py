"""model_io 特征 sidecar 自动补写单测。"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import lightgbm as lgb
import numpy as np
import yaml

MODEL_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(MODEL_ROOT / "src"))

from model_io import (  # noqa: E402
    features_sidecar_path,
    load_feature_list,
    resolve_model_features,
)


def _train_column_named_booster(n_features: int, out_path: Path) -> None:
    rng = np.random.RandomState(0)
    x = rng.randn(200, n_features).astype(np.float32)
    y = (rng.rand(200) > 0.9).astype(np.int8)
    ds = lgb.Dataset(x, label=y)
    booster = lgb.train({"objective": "binary", "verbosity": -1}, ds, num_boost_round=3)
    booster.save_model(str(out_path))


def test_auto_repair_sidecar_from_config(tmp_path: Path) -> None:
    feature_names = ["feat_a", "feat_b", "feat_c"]
    parquet_path = tmp_path / "train.parquet"
    import pandas as pd

    rows = {name: [1.0, 2.0] for name in feature_names}
    rows.update({"pu_label": [1, 0], "dataset_split": ["train", "val"], "unique_id": ["a", "b"]})
    pd.DataFrame(rows).to_parquet(parquet_path, index=False)

    config_path = tmp_path / "config.yaml"
    config_path.write_text(
        yaml.safe_dump(
            {
                "data": {
                    "input_path": str(parquet_path.name),
                    "feature_list_path": str((tmp_path / "features.txt").name),
                    "id_col": "unique_id",
                    "label_col": "pu_label",
                    "split_col": "dataset_split",
                    "train_split_value": "train",
                    "val_split_value": "val",
                }
            }
        ),
        encoding="utf-8",
    )
    (tmp_path / "features.txt").write_text("\n".join(feature_names) + "\n", encoding="utf-8")

    model_path = tmp_path / "model.txt"
    _train_column_named_booster(len(feature_names), model_path)
    assert load_feature_list(model_path) is None

    resolved = resolve_model_features(
        model_path,
        config_path=config_path,
        data_path=parquet_path,
        auto_repair=True,
    )
    assert resolved == feature_names
    sidecar = features_sidecar_path(model_path)
    assert sidecar.exists()
    assert json.loads(sidecar.read_text(encoding="utf-8")) == feature_names
