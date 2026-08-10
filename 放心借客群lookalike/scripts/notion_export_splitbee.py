#!/usr/bin/env python3
"""Export public Notion pages via splitbee API to Markdown (lookalike project)."""

from __future__ import annotations

import json
import re
import sys
import urllib.request
from pathlib import Path

API = "https://notion-api.splitbee.io/v1/page/{page_id}"


def fetch_page(page_id: str) -> dict:
    with urllib.request.urlopen(API.format(page_id=page_id), timeout=120) as resp:
        return json.load(resp)


def rich_to_md(title_arr) -> str:
    if not title_arr:
        return ""
    out: list[str] = []
    for seg in title_arr:
        if not isinstance(seg, list) or not seg:
            continue
        text = str(seg[0])
        fmt = seg[1] if len(seg) > 1 else []
        link = None
        if isinstance(fmt, list):
            for f in fmt:
                if f == "b":
                    text = f"**{text}**"
                elif f == "i":
                    text = f"*{text}*"
                elif isinstance(f, list) and f and f[0] == "a":
                    link = f[1]
                elif isinstance(f, list) and f and f[0] == "p":
                    text = f"[[子页面:{f[1]}]]"
        if link:
            text = f"[{text}]({link})"
        out.append(text)
    return "".join(out)


def get_block(blocks: dict, bid: str) -> dict | None:
    wrap = blocks.get(bid)
    if not wrap:
        return None
    val = wrap.get("value", {})
    if isinstance(val, dict) and "value" in val:
        val = val["value"]
    return val


def render_table(table_id: str, blocks: dict) -> str:
    tbl = get_block(blocks, table_id)
    if not tbl:
        return ""
    rows: list[list[str]] = []
    for rid in tbl.get("content", []) or []:
        row = get_block(blocks, rid)
        if not row or row.get("type") != "table_row":
            continue
        props = row.get("properties", {})
        cells = [rich_to_md(v) for _, v in sorted(props.items())]
        rows.append(cells)
    if not rows:
        return ""
    header, *body = rows
    lines = [
        "| " + " | ".join(header) + " |",
        "| " + " | ".join(["---"] * len(header)) + " |",
    ]
    for r in body:
        if len(r) < len(header):
            r = r + [""] * (len(header) - len(r))
        lines.append("| " + " | ".join(r[: len(header)]) + " |")
    return "\n".join(lines) + "\n"


def block_to_md(bid: str, blocks: dict, seen_tables: set[str]) -> str:
    val = get_block(blocks, bid)
    if not val:
        return ""
    btype = val.get("type")
    props = val.get("properties", {})
    title = rich_to_md(props.get("title", []))
    lines: list[str] = []

    if btype == "header":
        lines.append(f"\n## {title}\n")
    elif btype == "sub_header":
        lines.append(f"\n### {title}\n")
    elif btype == "sub_sub_header":
        lines.append(f"\n#### {title}\n")
    elif btype in ("text", "bulleted_list", "numbered_list"):
        if title:
            prefix = "- " if btype == "bulleted_list" else ""
            lines.append(f"{prefix}{title}\n")
    elif btype == "image":
        fn = title or "image.png"
        lines.append(f"\n> 图示（Notion 附件，未随仓库同步）：`{fn}`\n")
    elif btype == "page":
        slug = re.sub(r'[\\\\/:*?"<>|]', "_", title) or bid
        lines.append(f"\n- 子页面：[{title}]({slug}.md)（`{bid}`）\n")
    elif btype == "table":
        if bid not in seen_tables:
            seen_tables.add(bid)
            lines.append("\n" + render_table(bid, blocks) + "\n")
        return "".join(lines)
    elif btype == "table_row":
        return ""
    elif btype == "code":
        lang = rich_to_md(props.get("language", [])) or ""
        lines.append(f"\n```{lang}\n{title}\n```\n")
    else:
        if title:
            lines.append(f"{title}\n")

    for child in val.get("content", []) or []:
        child_val = get_block(blocks, child)
        if child_val and child_val.get("type") == "table":
            if child not in seen_tables:
                seen_tables.add(child)
                lines.append("\n" + render_table(child, blocks) + "\n")
        else:
            lines.append(block_to_md(child, blocks, seen_tables))
    return "".join(lines)


def page_to_markdown(page_id: str, data: dict, source_url: str) -> tuple[str, str]:
    root = data[page_id]["value"]["value"]
    title = rich_to_md(root.get("properties", {}).get("title", [])) or "untitled"
    parts = [
        f"# {title}\n",
        f"\n> 来源：[Notion]({source_url})  \n",
        f"> 页面 ID：`{page_id}`  \n",
        f"> 导出方式：`scripts/notion_export_splitbee.py`（splitbee 公开 API）\n",
    ]
    seen: set[str] = set()
    for child in root.get("content", []) or []:
        parts.append(block_to_md(child, data, seen))
    return title, "".join(parts)


def safe_filename(title: str) -> str:
    name = re.sub(r'[\\\\/:*?"<>|]', "_", title).strip() or "untitled"
    return f"{name}.md"


def main() -> int:
    out_dir = Path(__file__).resolve().parents[1] / "notion"
    out_dir.mkdir(parents=True, exist_ok=True)

    pages = [
        (
            "3ab617cf-3593-8086-ba0b-d957c04a7120",
            "https://treasure-fragrance-342.notion.site/lookalike-3ab617cf35938086ba0bd957c04a7120",
        ),
        (
            "3ae617cf-3593-80c7-b368-c9e3cd7828bb",
            "https://treasure-fragrance-342.notion.site/提额降价项目测试-3ae617cf359380c7b368c9e3cd7828bb",
        ),
    ]

    index_lines = [
        "# Notion 文档镜像（放心借 lookalike）\n",
        "\n同事 Notion 站点内容的 Markdown 快照，便于离线查阅与检索。\n",
        "\n## 页面\n",
    ]

    for pid, url in pages:
        data = fetch_page(pid)
        title, md = page_to_markdown(pid, data, url)
        fname = safe_filename(title)
        (out_dir / fname).write_text(md, encoding="utf-8")
        index_lines.append(f"- [{title}]({fname})（`{pid}`）\n")

    index_lines.append("\n## 嵌入资料（GitHub 同源 Markdown）\n")
    root = Path(__file__).resolve().parents[1]
    embedded = [
        "客群及其他相关表.md",
        "放心借特征变量.md",
        "朴道-外部字典.md",
        "百行-外部字典.md",
        "腾讯-外部字典.md",
    ]
    emb_dir = out_dir / "嵌入资料"
    emb_dir.mkdir(exist_ok=True)
    for name in embedded:
        src = root / name
        if not src.exists():
            continue
        text = src.read_text(encoding="utf-8")
        (emb_dir / name).write_text(text, encoding="utf-8")
        index_lines.append(f"- [{name}](嵌入资料/{name})\n")
        index_lines.append(f"  - 项目根目录副本：[../{name}](../{name})\n")

    index_lines.append("\n## 外部链接（Notion 正文中引用）\n")
    index_lines.append(
        "- [业务实验筛选条件（飞书表格）](https://weikezhijia.feishu.cn/sheets/DPOnsRCLXhBDGLtsx4EcySW8nlK?sheet=2DoSKF)\n"
    )

    (out_dir / "INDEX.md").write_text("".join(index_lines), encoding="utf-8")
    print(f"Wrote {out_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
