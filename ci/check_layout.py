#!/usr/bin/env python3
"""按 docs/pr-guide.md 的归位规则检查文件是否放在该放的地方。

用法:
    python3 ci/check_layout.py                  # 检查全仓
    python3 ci/check_layout.py --base origin/master
                                                # 只检查相对该基线的改动（PR 用）
退出码: 0 合规; 1 有文件放错位置
"""

import argparse
import os
import re
import subprocess
import sys

TOP_DIRS = {"skills", "tools", "vendor", "docs", "ci"}
ROOT_MD_ALLOWED = {"README.md", "CONTRIBUTING.md", "CHANGELOG.md"}
BINARY_SUFFIXES = (
    ".jar", ".class", ".rpm", ".zip", ".tgz", ".tar.gz", ".whl", ".so",
    ".bin", ".hpm", ".exe", ".dll", ".dylib", ".odt",
)
VENDOR_BINARY_SUFFIXES = (
    ".jar", ".class", ".rpm", ".zip", ".tgz", ".tar.gz", ".whl", ".so",
    ".bin", ".hpm", ".exe", ".dll", ".dylib",
)
SKILL_SCRIPT = re.compile(r"^skills/[^/]+/scripts/.+")
TOOL_FILE = re.compile(r"^tools/[^/]+/.+")
CI_FILE = re.compile(r"^ci/.+")
SKILL_REFERENCE = re.compile(r"^skills/[^/]+/references/.+")


def list_files(base=None):
    if base:
        args = ["git", "-c", "core.quotepath=false", "diff", "--name-only", "--diff-filter=ACMR", f"{base}...HEAD"]
    else:
        args = ["git", "-c", "core.quotepath=false", "ls-files", "--cached", "--others", "--exclude-standard"]
    result = subprocess.run(args, capture_output=True, text=True, check=False)
    if result.returncode != 0:
        print(result.stderr.strip())
        return None
    return [line for line in result.stdout.splitlines() if line.strip()]


def check(path):
    parts = path.split("/")
    problems = []
    vendor = path.startswith("vendor/")

    if path.endswith(VENDOR_BINARY_SUFFIXES if vendor else BINARY_SUFFIXES):
        problems.append("二进制与构建产物不入库，改放 Release 附件、LFS 或独立包")
        return problems

    if vendor:
        return problems

    if any(part == "references" for part in parts[:-1]) and not SKILL_REFERENCE.match(path):
        problems.append("references/ 只能出现在 skills/<name>/ 下")

    if len(parts) > 1 and parts[0] not in TOP_DIRS and not parts[0].startswith("."):
        problems.append(f"顶层目录只允许 {sorted(TOP_DIRS)}，新内容请归入其一")

    if len(parts) == 1 and path.endswith(".md") and path not in ROOT_MD_ALLOWED:
        problems.append(f"根目录只放 {sorted(ROOT_MD_ALLOWED)}，其余文档放 docs/")

    if path.endswith(".sh") and not (SKILL_SCRIPT.match(path) or TOOL_FILE.match(path) or CI_FILE.match(path)):
        problems.append("脚本应放 skills/<name>/scripts/、tools/<name>/ 或 ci/")

    if path.endswith(".py") and not (SKILL_SCRIPT.match(path) or TOOL_FILE.match(path) or CI_FILE.match(path)):
        if not path.startswith("vendor/"):
            problems.append("Python 脚本应放 ci/、skills/<name>/scripts/ 或 tools/<name>/")

    return problems


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", help="只检查相对该 git 基线的改动")
    args = parser.parse_args()

    files = list_files(args.base)
    if files is None:
        return 2

    scope = f"相对 {args.base} 的 {len(files)} 个文件" if args.base else f"{len(files)} 个跟踪文件"
    failures = 0
    for path in files:
        if not os.path.exists(path) and not args.base:
            continue
        for problem in check(path):
            failures += 1
            print(f"FAIL  {path}")
            print(f"        - {problem}")

    print(f"\n归位检查（{scope}）：{failures} 处不合规")
    if failures:
        print("规则见 docs/pr-guide.md")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
