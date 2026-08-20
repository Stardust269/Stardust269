#!/usr/bin/env python3
"""
用 LightGBM Top10 特征训练浅层决策树，探查是否存在「少量规则即可几乎分开种子/非种子」。

同事关注点：若几层分支就能极高精度区分，可能存在必然可分的强特征（含泄漏风险）。
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from sklearn.metrics import accuracy_score, classification_report, roc_auc_score
from sklearn.tree import DecisionTreeClassifier, export_text

MODEL_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(MODEL_ROOT / "src"))

from config_loader import load_config, resolve_path  # noqa: E402
from dataset import load_split_minimal  # noqa: E402
from memory_utils import release  # noqa: E402
from top_features import infer_model_path, load_top_feature_names  # noqa: E402
from tree_viz import (  # noqa: E402
    compute_node_statistics,
    format_recall_summary_text,
    save_decision_tree_plot,
    summarize_pred_seed_leaf_recall,
)


def _prepare_xy(df: pd.DataFrame, features: list[str], label_col: str):
    use = [c for c in features if c in df.columns]
    missing = [c for c in features if c not in df.columns]
    if missing:
        print(f"警告: 数据中缺失 {len(missing)} 个 Top 特征: {missing[:5]}")
    x = df[use].copy()
    for col in use:
        x[col] = pd.to_numeric(x[col], errors="coerce")
    y = df[label_col].astype(int).to_numpy()
    mask = np.isin(y, [0, 1]) & x.notna().all(axis=1).to_numpy()
    return x.loc[mask].to_numpy(dtype=np.float32), y[mask], use


def _leaf_stats(clf: DecisionTreeClassifier, x: np.ndarray, y: np.ndarray) -> pd.DataFrame:
    leaf_ids = clf.apply(x)
    rows = []
    for leaf in np.unique(leaf_ids):
        m = leaf_ids == leaf
        n = int(m.sum())
        pos = int(y[m].sum())
        neg = n - pos
        purity = max(pos, neg) / n if n else 0.0
        rows.append(
            {
                "leaf_id": int(leaf),
                "samples": n,
                "pos": pos,
                "neg": neg,
                "pos_rate": pos / n if n else 0.0,
                "purity": purity,
            }
        )
    return pd.DataFrame(rows).sort_values("purity", ascending=False)


def _eval_split(name: str, clf: DecisionTreeClassifier, x: np.ndarray, y: np.ndarray) -> dict:
    prob = clf.predict_proba(x)[:, 1]
    pred = (prob >= 0.5).astype(int)
    out = {
        "split": name,
        "n": int(len(y)),
        "n_pos": int((y == 1).sum()),
        "accuracy": float(accuracy_score(y, pred)),
    }
    if len(np.unique(y)) > 1:
        out["auc"] = float(roc_auc_score(y, prob))
    return out


def _run_test_eval(
    clf: DecisionTreeClassifier,
    used: list[str],
    test_path: Path,
    cfg: dict,
    config_path: Path,
    label_col: str,
    *,
    do_plot: bool,
    plot_out: Path | None,
    out_stem: Path,
) -> dict:
    """用 train 上拟合的决策树，在 test 集上评估并可选导出 test 节点统计图。"""
    print(f"\n>>> 加载 test: {test_path}")
    test_df = load_split_minimal(
        test_path,
        cfg,
        config_path,
        used,
        split_value=None,
        restrict_splits=False,
    )
    x_test, y_test, _ = _prepare_xy(test_df, used, label_col)
    release(test_df)

    test_m = _eval_split("test", clf, x_test, y_test)
    test_leaves = _leaf_stats(clf, x_test, y_test)
    test_node_stats = compute_node_statistics(clf, x_test, y_test)
    test_recall = summarize_pred_seed_leaf_recall(clf, test_node_stats, y_test)

    print("\n=== test 整体指标（train 拟合树，时间外评估）===")
    auc = test_m.get("auc")
    auc_s = f"{auc:.6f}" if auc is not None else "n/a"
    print(
        f"test: n={test_m['n']:,}, pos={test_m['n_pos']:,}, "
        f"accuracy={test_m['accuracy']:.4f}, auc={auc_s}"
    )

    print("\n=== test classification_report (threshold=0.5) ===")
    test_prob = clf.predict_proba(x_test)[:, 1]
    test_cr = classification_report(y_test, (test_prob >= 0.5).astype(int), digits=4)
    print(test_cr)

    print("\n=== test 叶节点纯度（前 10）===")
    print(test_leaves.head(10).to_string(index=False))

    print("\n=== test — Pred=SEED 叶节点种子召回 ===")
    print(format_recall_summary_text(test_recall))

    test_report = {
        "metrics": test_m,
        "classification_report": test_cr,
        "leaves_test": test_leaves.to_dict(orient="records"),
        "seed_leaf_recall_test": test_recall,
    }
    test_json = out_stem.with_name(f"{out_stem.name}_test.json")
    test_json.write_text(json.dumps(test_report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\ntest 指标已写入 {test_json}")

    if do_plot:
        test_plot = plot_out or out_stem.with_name(f"{out_stem.name}_test_tree.png")
        save_decision_tree_plot(
            clf,
            used,
            test_plot,
            x=x_test,
            y=y_test,
            node_stats=test_node_stats,
            recall_summary=test_recall,
        )
        print(f"test 决策树图已写入 {test_plot}（节点统计基于 test 样本）")
        test_report["plot_path"] = str(test_plot)

    return test_report


def main() -> None:
    parser = argparse.ArgumentParser(description="Top10 特征浅层决策树探查")
    parser.add_argument("--config", type=Path, default=MODEL_ROOT / "config_train_window.yaml")
    parser.add_argument("--importance", type=Path, default=None)
    parser.add_argument("--model", type=Path, default=None)
    parser.add_argument("--features-json", type=Path, default=None)
    parser.add_argument("--data", type=Path, default=None, help="train+val parquet")
    parser.add_argument("--top", type=int, default=10)
    parser.add_argument("--max-depth", type=int, default=4, help="树深度，越小规则越少")
    parser.add_argument("--min-samples-leaf", type=int, default=200)
    parser.add_argument("--out-dir", type=Path, default=MODEL_ROOT / "artifacts" / "dt_probe")
    parser.add_argument("--no-plot", action="store_true", help="不导出树结构图")
    parser.add_argument("--plot-out", type=Path, default=None, help="树图路径 .png/.pdf")
    parser.add_argument(
        "--test-data",
        type=Path,
        default=None,
        help="test_window.parquet；用 train 拟合的树做时间外评估",
    )
    parser.add_argument(
        "--artifact",
        type=Path,
        default=None,
        help="已有 dt_probe .joblib；跳过训练，仅在 --test-data 上评估",
    )
    parser.add_argument(
        "--plot-test",
        action="store_true",
        help="test 评估时额外导出 test 节点统计图（默认仅 train 图）",
    )
    args = parser.parse_args()
    do_plot = not args.no_plot

    cfg = load_config(args.config)
    data_path = args.data or resolve_path(cfg["data"]["input_path"], args.config)
    label_col = cfg["data"]["label_col"]

    # 仅从已有 joblib 在 test 上评估
    if args.artifact:
        if not args.test_data:
            raise SystemExit("使用 --artifact 时必须指定 --test-data")
        bundle = joblib.load(args.artifact)
        clf = bundle["clf"]
        used = bundle["feature_names"]
        out_stem = args.artifact.with_suffix("")
        print(f"已加载决策树: {args.artifact}")
        print("特征:", used)
        _run_test_eval(
            clf,
            used,
            args.test_data,
            cfg,
            args.config,
            label_col,
            do_plot=not args.no_plot,
            plot_out=args.plot_out,
            out_stem=out_stem,
        )
        return

    if not args.importance:
        raise SystemExit("请指定 --importance，或使用 --artifact 仅在 test 上评估")

    model_path = args.model or infer_model_path(args.importance)

    top_features = load_top_feature_names(
        args.importance,
        top=args.top,
        model_path=model_path,
        features_path=args.features_json,
    )
    print("Top 特征:", top_features)

    print("\n>>> 加载 train（仅 Top 特征列）...")
    train_df = load_split_minimal(
        data_path, cfg, args.config, top_features, split_value=cfg["data"]["train_split_value"]
    )
    x_train, y_train, used = _prepare_xy(train_df, top_features, label_col)
    release(train_df)

    print(">>> 加载 val...")
    val_df = load_split_minimal(
        data_path, cfg, args.config, top_features, split_value=cfg["data"]["val_split_value"]
    )
    x_val, y_val, _ = _prepare_xy(val_df, top_features, label_col)
    release(val_df)

    print(f">>> 训练决策树 max_depth={args.max_depth}, min_samples_leaf={args.min_samples_leaf} ...")
    clf = DecisionTreeClassifier(
        max_depth=args.max_depth,
        min_samples_leaf=args.min_samples_leaf,
        random_state=42,
        class_weight="balanced",
    )
    clf.fit(x_train, y_train)

    tree_rules = export_text(clf, feature_names=used, decimals=4)
    train_m = _eval_split("train", clf, x_train, y_train)
    val_m = _eval_split("val", clf, x_val, y_val)
    leaves = _leaf_stats(clf, x_train, y_train)

    print("\n=== 决策树规则（train 拟合） ===\n")
    print(tree_rules)

    print("\n=== 整体指标 ===")
    for m in [train_m, val_m]:
        auc = m.get("auc")
        auc_s = f"{auc:.6f}" if auc is not None else "n/a"
        print(
            f"{m['split']}: n={m['n']:,}, pos={m['n_pos']:,}, "
            f"accuracy={m['accuracy']:.4f}, auc={auc_s}"
        )

    print("\n=== val classification_report (threshold=0.5) ===")
    val_prob = clf.predict_proba(x_val)[:, 1]
    print(classification_report(y_val, (val_prob >= 0.5).astype(int), digits=4))

    print("\n=== train 叶节点纯度（越高越像「几条规则硬分开」）===")
    print(leaves.head(10).to_string(index=False))
    pure = leaves[leaves["purity"] >= 0.99]
    if not pure.empty:
        print(f"\n注意: {len(pure)} 个叶节点纯度≥99%，最大叶样本数={int(pure['samples'].max()):,}")

    node_stats = compute_node_statistics(clf, x_train, y_train)
    recall_summary = summarize_pred_seed_leaf_recall(clf, node_stats, y_train)
    print("\n" + format_recall_summary_text(recall_summary))

    args.out_dir.mkdir(parents=True, exist_ok=True)
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    stem = args.out_dir / f"dt_probe_top{args.top}_{ts}"
    report = {
        "top_features": used,
        "params": {
            "max_depth": args.max_depth,
            "min_samples_leaf": args.min_samples_leaf,
        },
        "metrics": {"train": train_m, "val": val_m},
        "leaves_train": leaves.to_dict(orient="records"),
        "tree_rules": tree_rules,
        "seed_leaf_recall": recall_summary,
    }
    (stem.with_suffix(".json")).write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    (stem.with_suffix(".txt")).write_text(tree_rules, encoding="utf-8")
    joblib.dump(
        {
            "clf": clf,
            "feature_names": used,
            "params": report["params"],
            "node_stats": {str(k): v for k, v in node_stats.items()},
            "seed_leaf_recall": recall_summary,
        },
        stem.with_suffix(".joblib"),
    )

    plot_path = None
    if do_plot:
        plot_path = args.plot_out or stem.with_name(f"{stem.name}_tree.png")
        save_decision_tree_plot(
            clf,
            used,
            plot_path,
            x=x_train,
            y=y_train,
            node_stats=node_stats,
            recall_summary=recall_summary,
        )
        print(f"决策树图已写入 {plot_path}（同目录另有 .csv 节点明细、.dot 源文件）")

    md = [
        "# 决策树探查（Top10 特征）",
        "",
        f"- 数据: `{data_path}`",
        f"- max_depth: {args.max_depth}",
        "",
        "## 特征",
        "",
        "\n".join(f"- {f}" for f in used),
        "",
        "## 指标",
        "",
        f"- train accuracy: {train_m['accuracy']:.4f}, auc: {train_m.get('auc', 'n/a')}",
        f"- val accuracy: {val_m['accuracy']:.4f}, auc: {val_m.get('auc', 'n/a')}",
        "",
    ]
    if plot_path:
        md.extend(
            [
                "## 结构图",
                "",
                "节点框内字段说明：`seeds`=种子用户数，`seed% in node`=该节点内种子占比，"
                "`seed recall`=该节点种子数/全量种子（累计召回率）。",
                "",
                f"![decision tree]({plot_path.name})",
                "",
                "## 预测=种子的叶节点 — 种子召回",
                "",
                f"- 全部种子: {recall_summary['total_seed']:,}",
                f"- 预测=SEED 的叶节点召回种子: {recall_summary['recalled_in_pred1_leaves']:,} "
                f"({recall_summary['recall_rate']*100:.2f}%)",
                "",
                f"节点明细 CSV: `{plot_path.with_suffix('.csv').name}`",
                "",
            ]
        )
    md.extend(
        [
            "## 规则",
            "",
            "```",
            tree_rules,
            "```",
        ]
    )
    (stem.with_suffix(".md")).write_text("\n".join(md), encoding="utf-8")
    print(f"\n报告已写入 {stem}.{{md,txt,json,joblib}}")

    if args.test_data:
        test_report = _run_test_eval(
            clf,
            used,
            args.test_data,
            cfg,
            args.config,
            label_col,
            do_plot=not args.no_plot,
            plot_out=args.plot_out.with_name(f"{stem.name}_test_tree.png") if args.plot_out else None,
            out_stem=stem,
        )
        report["test"] = test_report
        (stem.with_suffix(".json")).write_text(
            json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        md.append("")
        md.append("## Test（时间外）")
        md.append("")
        tm = test_report["metrics"]
        md.append(
            f"- test accuracy: {tm['accuracy']:.4f}, auc: {tm.get('auc', 'n/a')}"
        )
        sr = test_report["seed_leaf_recall_test"]
        md.append(
            f"- test Pred=SEED 叶节点召回种子: {sr['recalled_in_pred1_leaves']:,}/"
            f"{sr['total_seed']:,} ({sr['recall_rate']*100:.2f}%)"
        )
        if test_report.get("plot_path"):
            md.append(f"- test 结构图: `{Path(test_report['plot_path']).name}`")
        (stem.with_suffix(".md")).write_text("\n".join(md), encoding="utf-8")


if __name__ == "__main__":
    main()
