#!/usr/bin/env python3
"""校验 Markdown 中的相对链接是否可解析。

只检查本地路径，不访问网络；跳过 http(s)、mailto、页内锚点和代码块内的示例。
用法: python3 ci/check_links.py
"""

import os
import re
import sys
import urllib.parse

LINK = re.compile(r"!?\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
FENCE = re.compile(r"^\s*(```|~~~)")
SKIP_DIRS = {".git", "node_modules", "__pycache__", ".venv"}
SKIP_PREFIXES = ("#", "http://", "https://", "mailto:", "tel:", "ftp://")


def strip_code_fences(text):
    out = []
    fence = None
    for line in text.splitlines():
        match = FENCE.match(line)
        if match:
            fence = None if fence else match.group(1)
            out.append("")
            continue
        out.append("" if fence else line)
    return "\n".join(out)


def main():
    root = os.getcwd()
    broken = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(d for d in dirnames if d not in SKIP_DIRS)
        for name in sorted(filenames):
            if not name.endswith(".md"):
                continue
            path = os.path.join(dirpath, name)
            try:
                text = open(path, encoding="utf-8", errors="replace").read()
            except OSError as exc:
                print(f"无法读取: {path}: {exc}")
                continue
            for match in LINK.finditer(strip_code_fences(text)):
                target = match.group(1).strip()
                if not target or target.startswith(SKIP_PREFIXES):
                    continue
                local = urllib.parse.unquote(target.split("#", 1)[0].split("?", 1)[0])
                if not local:
                    continue
                if not os.path.exists(os.path.normpath(os.path.join(dirpath, local))):
                    broken.append((os.path.relpath(path, root), target))
    for page, target in broken:
        print(f"断链: {page} -> {target}")
    if broken:
        print(f"共 {len(broken)} 处断链")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
