from __future__ import annotations

from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
from sklearn.tree import DecisionTreeClassifier, plot_tree


def save_decision_tree_plot(
    clf: DecisionTreeClassifier,
    feature_names: list[str],
    out_path: Path,
    *,
    class_names: list[str] | None = None,
    figsize: tuple[float, float] = (28, 16),
    dpi: int = 150,
    fontsize: int = 7,
) -> Path:
    """将决策树保存为 PNG（若 out_path 以 .pdf 结尾则保存 PDF）。"""
    out_path = Path(out_path)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    class_names = class_names or ["neg(0)", "seed(1)"]

    fig, ax = plt.subplots(figsize=figsize)
    plot_tree(
        clf,
        feature_names=feature_names,
        class_names=class_names,
        filled=True,
        rounded=True,
        fontsize=fontsize,
        impurity=True,
        proportion=True,
        ax=ax,
    )
    ax.set_title("Decision Tree Probe (Top features)", fontsize=12)
    fig.tight_layout()
    fmt = "pdf" if out_path.suffix.lower() == ".pdf" else "png"
    fig.savefig(out_path, dpi=dpi, bbox_inches="tight", format=fmt)
    plt.close(fig)
    return out_path
