"""
从 Iceberg 表经 dtools 拉取到本地 parquet，分片下载并显示 tqdm 进度。

用法（IDE / Jupyter）:
  python scripts/download_training_pu.py
或在 notebook 里 import 后调用 download_table_to_parquet(...)

若 get_as_frame 不支持 SQL 字符串，请把 run_query 改成你们 dtools 的 SQL 接口。
"""
from __future__ import annotations

import argparse
import inspect
import sys
import threading
import time
from pathlib import Path

import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq
from tqdm.auto import tqdm

MODEL_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_TABLE = "lj_iceberg.ai_decision_dev.fxj_lookalike_pu_training_1"
DEFAULT_OUT = MODEL_ROOT / "data" / "training_pu.parquet"


def _import_dtools():
    try:
        import dtools  # type: ignore
    except ImportError as e:
        raise ImportError("需要在内网 Jupyter 环境安装 dtools") from e
    return dtools


def run_query(dtools, sql: str) -> pd.DataFrame:
    """优先 SQL；若 get_as_frame 仅支持表名，可在此替换为 dtools.query 等。"""
    fn = dtools.get_as_frame
    params = inspect.signature(fn).parameters
    if "sql" in params:
        return fn(sql=sql)
    return fn(sql)


def count_rows(dtools, table: str) -> int:
    df = run_query(dtools, f"select count(1) as cnt from {table}")
    col = "cnt" if "cnt" in df.columns else df.columns[0]
    return int(df[col].iloc[0])


def chunk_sql(table: str, chunk_index: int, num_chunks: int, key_col: str) -> str:
    # 与 build_pu_training_table.sql 中 hash 写法一致，便于引擎优化
    return (
        f"select * from {table} "
        f"where abs(hash(concat({key_col}, ''))) % {num_chunks} = {chunk_index}"
    )


def download_table_to_parquet(
    table: str,
    out_path: Path,
    *,
    num_chunks: int = 20,
    key_col: str = "unique_id",
    show_dtools_progress: bool = True,
) -> Path:
    dtools = _import_dtools()
    out_path = Path(out_path)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    total = count_rows(dtools, table)
    print(f"表 {table} 约 {total:,} 行，分 {num_chunks} 片下载 → {out_path}")

    writer: pq.ParquetWriter | None = None
    downloaded = 0

    with tqdm(total=total, desc="下载", unit="行", unit_scale=True, miniters=1) as bar:
        for i in range(num_chunks):
            sql = chunk_sql(table, i, num_chunks, key_col)
            if show_dtools_progress and hasattr(dtools, "get_as_frame"):
                sig = inspect.signature(dtools.get_as_frame)
                if "progress" in sig.parameters:
                    part = dtools.get_as_frame(sql, progress=True)
                elif "show_progress" in sig.parameters:
                    part = dtools.get_as_frame(sql, show_progress=True)
                else:
                    part = run_query(dtools, sql)
            else:
                part = run_query(dtools, sql)

            n = len(part)
            if n == 0:
                bar.set_postfix_str(f"片 {i + 1}/{num_chunks} 空")
                continue

            table_pa = pa.Table.from_pandas(part, preserve_index=False)
            if writer is None:
                writer = pq.ParquetWriter(out_path, table_pa.schema)
            writer.write_table(table_pa)
            downloaded += n
            bar.update(n)
            bar.set_postfix_str(f"片 {i + 1}/{num_chunks} 本片 {n:,}")

    if writer is not None:
        writer.close()
    else:
        raise RuntimeError("未读到任何数据，请检查表名与分片条件")

    if downloaded != total:
        print(
            f"提示: 已下载 {downloaded:,} 行，count 为 {total:,}，"
            "若不一致请查重复/过滤或调大 num_chunks"
        )

    return out_path


def _heartbeat_while_loading(msg: str, stop_event: threading.Event) -> None:
    start = time.time()
    while not stop_event.wait(1.0):
        elapsed = int(time.time() - start)
        sys.stdout.write(f"\r{msg} … 已等待 {elapsed}s（整表拉取无分片进度）")
        sys.stdout.flush()
    sys.stdout.write("\n")


def download_whole_table_simple(
    table: str,
    out_path: Path,
    *,
    use_heartbeat: bool = True,
) -> Path:
    """与原先单行 get_as_frame(表名) 等价，仅增加等待心跳 + 写入提示。"""
    dtools = _import_dtools()
    out_path = Path(out_path)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    stop = threading.Event()
    hb = None
    if use_heartbeat:
        hb = threading.Thread(
            target=_heartbeat_while_loading,
            args=(f"dtools 读取 {table}", stop),
            daemon=True,
        )
        hb.start()

    try:
        df_data = dtools.get_as_frame(table)
    finally:
        stop.set()
        if hb is not None:
            hb.join(timeout=2)

    with tqdm(total=1, desc="写入 parquet", bar_format="{desc}: {percentage:3.0f}%|{bar}") as bar:
        df_data.to_parquet(out_path, index=False)
        bar.update(1)

    print(f"====download success======  {len(df_data):,} 行 → {out_path}")
    return out_path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--table", default=DEFAULT_TABLE)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--chunks", type=int, default=20)
    parser.add_argument("--key-col", default="unique_id")
    parser.add_argument(
        "--whole",
        action="store_true",
        help="整表一次 get_as_frame（仅心跳，无真实行级进度）",
    )
    args = parser.parse_args()

    if args.whole:
        download_whole_table_simple(args.table, args.out)
    else:
        path = download_table_to_parquet(
            args.table,
            args.out,
            num_chunks=args.chunks,
            key_col=args.key_col,
        )
        print("====download success======", path)


if __name__ == "__main__":
    main()
