"""tree_viz DOT 语法回归：千分位逗号会导致 graphviz 解析失败。"""

from __future__ import annotations

import re
import sys
from pathlib import Path

import numpy as np
from sklearn.tree import DecisionTreeClassifier

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from tree_viz import build_tree_dot, compute_node_statistics, summarize_pred_seed_leaf_recall  # noqa: E402


def test_dot_has_no_thousand_separators_in_labels():
    rng = np.random.default_rng(0)
    x = rng.random((5000, 3))
    y = (x[:, 0] > 0.5).astype(int)
    clf = DecisionTreeClassifier(max_depth=3, random_state=0)
    clf.fit(x, y)
    features = ["f0", "f1", "f2"]
    stats = compute_node_statistics(clf, x, y)
    recall = summarize_pred_seed_leaf_recall(clf, stats, y)
    dot = build_tree_dot(clf, features, stats, recall)

    # 图标题行不应含 1,234 这类千分位
    title_line = [ln for ln in dot.splitlines() if ln.strip().startswith("label=")][0]
    assert not re.search(r"\d,\d{3}", title_line), title_line

    # HTML 节点标签内同样禁止千分位逗号
    for ln in dot.splitlines():
        if " [label=<" in ln:
            assert not re.search(r"\d,\d{3}", ln), ln

    assert "seeds:" in dot
    assert "seed recall:" in dot
