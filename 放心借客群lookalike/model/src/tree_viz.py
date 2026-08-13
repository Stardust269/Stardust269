from __future__ import annotations

import shutil
import subprocess
import tempfile
from pathlib import Path
from typing import Any

import numpy as np
import pandas as pd
from sklearn.tree import DecisionTreeClassifier


def compute_node_statistics(
    clf: DecisionTreeClassifier,
    x: np.ndarray,
    y: np.ndarray,
) -> dict[int, dict[str, Any]]:
    """统计每个节点落入的样本数、种子数、节点内种子占比、相对全量种子召回率。"""
    decision = clf.decision_path(x)
    if hasattr(decision, "toarray"):
        decision = decision.toarray()
    y = np.asarray(y).astype(int)
    total_seed = int(y.sum())
    n_nodes = clf.tree_.node_count
    tree = clf.tree_
    stats: dict[int, dict[str, Any]] = {}

    for node_id in range(n_nodes):
        mask = decision[:, node_id] > 0
        n = int(mask.sum())
        pos = int(y[mask].sum()) if n else 0
        neg = n - pos
        if tree.feature[node_id] >= 0:
            node_type = "split"
            pred_class = None
        else:
            node_type = "leaf"
            pred_class = int(np.argmax(tree.value[node_id][0]))

        stats[node_id] = {
            "node_id": node_id,
            "node_type": node_type,
            "pred_class": pred_class,
            "n": n,
            "pos": pos,
            "neg": neg,
            "pos_rate": float(pos / n) if n else 0.0,
            "seed_recall": float(pos / total_seed) if total_seed else 0.0,
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
                "seed_rate_in_node": st["pos_rate"],
                "seed_recall": st["seed_recall"],
            }
        )

    return {
        "total_seed": total_pos,
        "recalled_in_pred1_leaves": int(recalled),
        "recall_rate": float(recalled / total_pos) if total_pos else 0.0,
        "pred1_leaf_count": len(leaves),
        "leaves": leaves,
    }


def export_node_stats_table(
    clf: DecisionTreeClassifier,
    feature_names: list[str],
    node_stats: dict[int, dict[str, Any]],
    out_path: Path,
) -> Path:
    """导出每个节点的种子数量/占比/召回率表（CSV）。"""
    tree = clf.tree_
    rows = []
    for node_id, st in node_stats.items():
        row = dict(st)
        if tree.feature[node_id] >= 0:
            feat = feature_names[tree.feature[node_id]]
            row["split_rule"] = f"{feat} <= {tree.threshold[node_id]:.4f}"
        else:
            pred = "seed(1)" if st["pred_class"] == 1 else "neg(0)"
            row["split_rule"] = f"LEAF pred={pred}"
        rows.append(row)

    df = pd.DataFrame(rows).sort_values("node_id")
    cols = [
        "node_id",
        "node_type",
        "split_rule",
        "pred_class",
        "n",
        "pos",
        "neg",
        "pos_rate",
        "seed_recall",
    ]
    df = df[[c for c in cols if c in df.columns]]
    out_path = Path(out_path)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(out_path, index=False, encoding="utf-8-sig")
    return out_path


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
    total_seed: int,
) -> str:
    """节点标签仅用 ASCII + 数字，避免 graphviz/matplotlib 中文乱码。"""
    tree = clf.tree_
    st = stats[node_id]
    pos_pct = st["pos_rate"] * 100.0
    recall_pct = st["seed_recall"] * 100.0

    if tree.feature[node_id] >= 0:
        feat = feature_names[tree.feature[node_id]]
        thr = tree.threshold[node_id]
        title = _dot_escape(f"{feat} &lt;= {thr:.4f}")
        kind = "SPLIT"
    else:
        pred = int(np.argmax(tree.value[node_id][0]))
        pred_name = "SEED(1)" if pred == 1 else "NEG(0)"
        title = _dot_escape(f"LEAF pred={pred_name}")
        kind = "LEAF"

    lines = [
        f"<B>{title}</B>",
        f"<FONT POINT-SIZE='9'>{kind}</FONT>",
        f"samples: {st['n']:,}",
        f"seeds: {st['pos']:,}",
        f"seed% in node: {pos_pct:.1f}%",
        f"seed recall: {recall_pct:.1f}%",
        f"non-seed: {st['neg']:,}",
    ]
    return f"<{'<BR/>'.join(lines)}>"


def _node_fillcolor(node_id: int, clf: DecisionTreeClassifier) -> str:
    tree = clf.tree_
    if tree.feature[node_id] >= 0:
        return "#ffffff"
    values = tree.value[node_id][0]
    pred = int(np.argmax(values))
    return "#fb9a99" if pred == 1 else "#a6cee3"


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
        f"Pred=SEED leaves recall seeds {recalled:,}/{total:,} ({recall_pct:.1f}%)"
    )

    lines = [
        "digraph Tree {",
        'graph [rankdir=TB, splines=ortho, nodesep=0.45, ranksep=0.55];',
        'node [shape=box, style="rounded,filled", fontname="Helvetica", fontsize=10];',
        'edge [fontname="Helvetica", fontsize=9];',
        f'label="{_dot_escape(graph_title)}", labelloc=t, fontsize=13;',
        "",
    ]

    for node_id in range(tree.node_count):
        label = _node_html_label(
            node_id, clf, feature_names, node_stats, recall_summary["total_seed"]
        )
        fillcolor = _node_fillcolor(node_id, clf)
        lines.append(f'{node_id} [label={label}, fillcolor="{fillcolor}"];')

    for node_id in range(tree.node_count):
        if tree.feature[node_id] < 0:
            continue
        left = int(tree.children_left[node_id])
        right = int(tree.children_right[node_id])
        lines.append(f'{node_id} -> {left} [label="Y"];')
        lines.append(f'{node_id} -> {right} [label="N"];')

    lines.append("}")
    return "\n".join(lines)


def _render_dot_with_binary(dot: str, out_path: Path, fmt: str) -> Path:
    """优先调用系统 dot 命令渲染，避免 Python graphviz 配置问题。"""
    dot_bin = shutil.which("dot")
    if not dot_bin:
        raise RuntimeError("未找到 dot 可执行文件，请安装 graphviz (yum/apt install graphviz)")

    out_path = out_path.with_suffix(f".{fmt}")
    with tempfile.NamedTemporaryFile(mode="w", suffix=".dot", delete=False, encoding="utf-8") as f:
        f.write(dot)
        dot_file = f.name

    try:
        subprocess.run(
            [dot_bin, f"-T{fmt}", dot_file, "-o", str(out_path)],
            check=True,
            capture_output=True,
            text=True,
        )
    except subprocess.CalledProcessError as exc:
        raise RuntimeError(f"dot 渲染失败: {exc.stderr}") from exc
    finally:
        Path(dot_file).unlink(missing_ok=True)

    return out_path


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

    dot_path = out_path.with_suffix(".dot")
    dot_path.write_text(dot, encoding="utf-8")
    csv_path = export_node_stats_table(clf, feature_names, node_stats, out_path.with_suffix(".csv"))

    try:
        out_path = _render_dot_with_binary(dot, out_path, fmt)
    except Exception as exc1:
        try:
            import graphviz

            stem = out_path.with_suffix("")
            graphviz.Source(dot).render(filename=str(stem), format=fmt, cleanup=True)
            out_path = stem.with_suffix(f".{fmt}")
        except Exception as exc2:
            raise RuntimeError(
                "无法渲染决策树图。请安装 graphviz:\n"
                "  yum install graphviz   # 或 apt install graphviz\n"
                "  pip install graphviz\n"
                f"已保存: {dot_path}\n"
                f"已保存: {csv_path}\n"
                f"可手动: dot -Tpng {dot_path} -o tree.png\n"
                f"错误: {exc1}; {exc2}"
            ) from exc2

    print(f"节点明细表已写入 {csv_path}")
    return out_path, recall_summary, node_stats


def format_recall_summary_text(recall_summary: dict[str, Any]) -> str:
    s = recall_summary
    lines = [
        "=== Pred=SEED(1) leaves — seed recall summary ===",
        f"total seeds: {s['total_seed']:,}",
        f"pred=SEED leaf count: {s['pred1_leaf_count']}",
        f"seeds in pred=SEED leaves: {s['recalled_in_pred1_leaves']:,}",
        f"seed recall rate: {s['recall_rate']*100:.2f}%",
        "",
        "leaf details:",
    ]
    for leaf in s["leaves"]:
        lines.append(
            f"  - leaf#{leaf['node_id']}: samples={leaf['samples']:,}, "
            f"seeds={leaf['seed_count']:,} ({leaf['seed_rate_in_node']*100:.1f}% in node), "
            f"seed_recall={leaf['seed_recall']*100:.1f}%"
        )
    return "\n".join(lines)
