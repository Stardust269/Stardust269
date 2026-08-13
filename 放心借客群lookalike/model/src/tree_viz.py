from __future__ import annotations

from pathlib import Path
from typing import Any

import numpy as np
from sklearn.tree import DecisionTreeClassifier


def compute_node_statistics(
    clf: DecisionTreeClassifier,
    x: np.ndarray,
    y: np.ndarray,
) -> dict[int, dict[str, Any]]:
    """统计每个节点（含内部节点）落入的样本数、种子数、种子占比。"""
    decision = clf.decision_path(x)
    if hasattr(decision, "toarray"):
        decision = decision.toarray()
    y = np.asarray(y).astype(int)
    n_nodes = clf.tree_.node_count
    stats: dict[int, dict[str, Any]] = {}
    for node_id in range(n_nodes):
        mask = decision[:, node_id] > 0
        n = int(mask.sum())
        pos = int(y[mask].sum()) if n else 0
        neg = n - pos
        stats[node_id] = {
            "n": n,
            "pos": pos,
            "neg": neg,
            "pos_rate": float(pos / n) if n else 0.0,
        }
    return stats


def summarize_pred_seed_leaf_recall(
    clf: DecisionTreeClassifier,
    node_stats: dict[int, dict[str, Any]],
    y: np.ndarray,
) -> dict[str, Any]:
    """汇总「预测为种子(class=1)」的叶节点一共召回了多少种子。"""
    tree = clf.tree_
    total_pos = int(np.asarray(y).astype(int).sum())
    recalled = 0
    leaves: list[dict[str, Any]] = []

    for node_id in range(tree.node_count):
        if tree.feature[node_id] >= 0:
            continue
        values = tree.value[node_id][0]
        pred_class = int(np.argmax(values))
        if pred_class != 1:
            continue
        st = node_stats[node_id]
        recalled += st["pos"]
        leaves.append(
            {
                "node_id": node_id,
                "samples": st["n"],
                "seed_count": st["pos"],
                "seed_rate": st["pos_rate"],
            }
        )

    return {
        "total_seed": total_pos,
        "recalled_in_pred1_leaves": int(recalled),
        "recall_rate": float(recalled / total_pos) if total_pos else 0.0,
        "pred1_leaf_count": len(leaves),
        "leaves": leaves,
    }


def _dot_escape(text: str) -> str:
    return (
        str(text)
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )


def _node_html_label(
    node_id: int,
    clf: DecisionTreeClassifier,
    feature_names: list[str],
    stats: dict[int, dict[str, Any]],
) -> str:
    tree = clf.tree_
    st = stats[node_id]
    pos_pct = st["pos_rate"] * 100.0

    if tree.feature[node_id] >= 0:
        feat = feature_names[tree.feature[node_id]]
        thr = tree.threshold[node_id]
        title = f"{_dot_escape(feat)} &lt;= {thr:.4f}"
        kind = "内部节点"
    else:
        values = tree.value[node_id][0]
        pred = int(np.argmax(values))
        pred_name = "种子(1)" if pred == 1 else "非种子(0)"
        title = f"叶节点 预测={pred_name}"
        kind = "叶节点"

    lines = [
        f"<B>{title}</B>",
        f"<FONT POINT-SIZE='10'>{kind}</FONT>",
        f"samples: {st['n']:,}",
        f"种子: {st['pos']:,} ({pos_pct:.1f}%)",
        f"非种子: {st['neg']:,}",
    ]
    body = "<BR/>".join(lines)
    return f"<{body}>"


def _node_fillcolor(node_id: int, clf: DecisionTreeClassifier) -> str:
    tree = clf.tree_
    if tree.feature[node_id] >= 0:
        return "#ffffff"
    values = tree.value[node_id][0]
    pred = int(np.argmax(values))
    return "#fb9a99" if pred == 1 else "#a6cee3"  # 种子叶偏红，非种子偏蓝


def build_tree_dot(
    clf: DecisionTreeClassifier,
    feature_names: list[str],
    node_stats: dict[int, dict[str, Any]],
    recall_summary: dict[str, Any],
) -> str:
    tree = clf.tree_
    recalled = recall_summary["recalled_in_pred1_leaves"]
    total = recall_summary["total_seed"]
    recall_pct = recall_summary["recall_rate"] * 100.0
    graph_title = (
        f"预测=种子的叶节点 共召回种子 {recalled:,}/{total:,} ({recall_pct:.1f}%)"
    )

    lines = [
        "digraph Tree {",
        'graph [rankdir=TB, splines=ortho, nodesep=0.4, ranksep=0.5];',
        'node [shape=box, style="rounded,filled", fontname="Helvetica"];',
        'edge [fontname="Helvetica", fontsize=10];',
        f'label="{_dot_escape(graph_title)}", labelloc=t, fontsize=14;',
        "",
    ]

    for node_id in range(tree.node_count):
        label = _node_html_label(node_id, clf, feature_names, node_stats)
        fillcolor = _node_fillcolor(node_id, clf)
        lines.append(f'{node_id} [label={label}, fillcolor="{fillcolor}"];')

    for node_id in range(tree.node_count):
        if tree.feature[node_id] < 0:
            continue
        left = int(tree.children_left[node_id])
        right = int(tree.children_right[node_id])
        lines.append(f'{node_id} -> {left} [label="是", fontsize=9];')
        lines.append(f'{node_id} -> {right} [label="否", fontsize=9];')

    lines.append("}")
    return "\n".join(lines)


def save_decision_tree_plot(
    clf: DecisionTreeClassifier,
    feature_names: list[str],
    out_path: Path,
    *,
    x: np.ndarray | None = None,
    y: np.ndarray | None = None,
    node_stats: dict[int, dict[str, Any]] | None = None,
    recall_summary: dict[str, Any] | None = None,
    dpi: int = 150,
) -> tuple[Path, dict[str, Any], dict[int, dict[str, Any]]]:
    """
    导出带「种子占比」标注的决策树图（PNG/PDF/SVG）。
    需传入训练集 x,y 用于统计各节点种子占比；或传入预计算的 node_stats。
    """
    out_path = Path(out_path)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    if node_stats is None:
        if x is None or y is None:
            raise ValueError("请提供 x,y 或预计算的 node_stats")
        node_stats = compute_node_statistics(clf, x, y)
    if recall_summary is None:
        if y is None:
            raise ValueError("计算叶节点召回汇总需要 y")
        recall_summary = summarize_pred_seed_leaf_recall(clf, node_stats, y)

    dot = build_tree_dot(clf, feature_names, node_stats, recall_summary)
    fmt = out_path.suffix.lower().lstrip(".") or "png"
    if fmt not in {"png", "pdf", "svg"}:
        fmt = "png"
        out_path = out_path.with_suffix(".png")

    try:
        import graphviz

        stem = out_path.with_suffix("")
        src = graphviz.Source(dot)
        src.render(filename=str(stem), format=fmt, cleanup=True)
        out_path = stem.with_suffix(f".{fmt}")
    except Exception as exc:
        out_path = _save_matplotlib_fallback(clf, feature_names, out_path, recall_summary, dpi=dpi)
        dot_path = out_path.with_suffix(".dot")
        dot_path.write_text(dot, encoding="utf-8")
        print(f"警告: graphviz 不可用 ({exc})，已回退 matplotlib 并保存 {dot_path}")

    return out_path, recall_summary, node_stats


def _save_matplotlib_fallback(
    clf: DecisionTreeClassifier,
    feature_names: list[str],
    out_path: Path,
    recall_summary: dict[str, Any],
    *,
    dpi: int,
) -> Path:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from sklearn.tree import plot_tree

    out_path = out_path.with_suffix(".png")
    fig, ax = plt.subplots(figsize=(28, 16))
    plot_tree(
        clf,
        feature_names=feature_names,
        class_names=["非种子(0)", "种子(1)"],
        filled=True,
        rounded=True,
        fontsize=7,
        proportion=True,
        impurity=True,
        ax=ax,
    )
    s = recall_summary
    title = (
        f"预测=种子的叶节点 召回种子 {s['recalled_in_pred1_leaves']:,}/"
        f"{s['total_seed']:,} ({s['recall_rate']*100:.1f}%)"
    )
    ax.set_title(title, fontsize=12)
    fig.tight_layout()
    fig.savefig(out_path, dpi=dpi, bbox_inches="tight")
    plt.close(fig)
    return out_path


def format_recall_summary_text(recall_summary: dict[str, Any]) -> str:
    s = recall_summary
    lines = [
        "=== 预测=种子(1) 的叶节点 — 种子召回汇总 ===",
        f"全部种子用户: {s['total_seed']:,}",
        f"预测=种子的叶节点数: {s['pred1_leaf_count']}",
        f"这些叶节点内种子合计: {s['recalled_in_pred1_leaves']:,}",
        f"种子召回率: {s['recall_rate']*100:.2f}%",
        "",
        "各叶节点明细:",
    ]
    for leaf in s["leaves"]:
        lines.append(
            f"  - 叶#{leaf['node_id']}: samples={leaf['samples']:,}, "
            f"种子={leaf['seed_count']:,} ({leaf['seed_rate']*100:.1f}%)"
        )
    return "\n".join(lines)
