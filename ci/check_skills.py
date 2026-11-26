#!/usr/bin/env python3
"""校验 skill 目录是否符合 agentskills 规范。

规范: https://github.com/agentskills/agentskills/blob/main/docs/specification.mdx
用法: python3 ci/check_skills.py [--root DIR]...
退出码: 0 全部合规; 1 存在违规
"""

import os
import re
import sys

NAME_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
KEY_RE = re.compile(r"^([A-Za-z0-9_.-]+):\s*(.*)$")
SKILL_ENTRY = "SKILL.md"
RESOURCE_DIRS = {".git", "scripts", "references", "assets", "images"}
NON_NAME_CHARS = re.compile(r"[^a-z0-9-]")
MAX_NAME = 64
MAX_DESCRIPTION = 1024
MAX_COMPATIBILITY = 500
MAX_SKILL_LINES = 500
KNOWN_KEYS = {"name", "description", "license", "compatibility", "metadata", "allowed-tools"}
NON_STRING_SCALAR = re.compile(r"^(-?\d+(\.\d+)?|true|false|null|~)$", re.I)


class RawScalar(str):
    """YAML 中未加引号的数字/布尔/null，语义上不是字符串。"""


def unquote(value):
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        return value[1:-1]
    return value


def parse_frontmatter(text):
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return None
    end = next((i for i in range(1, len(lines)) if lines[i].strip() == "---"), None)
    if end is None:
        return None
    data = {}
    i = 1
    while i < end:
        match = KEY_RE.match(lines[i])
        if not match:
            i += 1
            continue
        key, rest = match.group(1), match.group(2).strip()
        if rest not in ("", ">-", ">", "|-", "|"):
            data[key] = unquote(rest)
            i += 1
            continue
        block = []
        i += 1
        while i < end and (not lines[i].strip() or lines[i][:1] in (" ", "\t")):
            block.append(lines[i].strip())
            i += 1
        if rest.startswith(">"):
            data[key] = " ".join(part for part in block if part)
        elif rest.startswith("|"):
            data[key] = "\n".join(block).strip()
        else:
            sub = {}
            for part in block:
                sub_match = KEY_RE.match(part)
                if not sub_match:
                    continue
                raw = sub_match.group(2).strip()
                if raw[:1] in "\"'":
                    sub[sub_match.group(1)] = unquote(raw)
                elif NON_STRING_SCALAR.match(raw):
                    sub[sub_match.group(1)] = RawScalar(raw)
                else:
                    sub[sub_match.group(1)] = raw
            data[key] = sub
    return data


def discover(roots):
    found = []
    for root in roots:
        if not os.path.isdir(root):
            continue
        if os.path.isfile(os.path.join(root, SKILL_ENTRY)):
            found.append((root, None))
            continue
        for entry in sorted(os.listdir(root)):
            path = os.path.join(root, entry)
            if os.path.isdir(path) and entry not in RESOURCE_DIRS:
                found.append((path, sorted(os.listdir(path))))
    return found


def validate(path, listing):
    errors, warnings = [], []
    entry = os.path.join(path, SKILL_ENTRY)

    if not os.path.isfile(entry):
        near = [f for f in (listing or []) if "skill" in f.lower() and f.endswith(".md")]
        if near:
            errors.append(f"入口文件必须命名为 {SKILL_ENTRY}，实际为: {', '.join(near)}")
        else:
            errors.append(f"缺少 {SKILL_ENTRY}")
        return errors, warnings

    text = open(entry, encoding="utf-8", errors="replace").read()
    front = parse_frontmatter(text)
    if front is None:
        errors.append(f"{SKILL_ENTRY} 必须以 YAML frontmatter（首行 ---）开头并以 --- 闭合")
        return errors, warnings

    name = front.get("name")
    dirname = os.path.basename(os.path.abspath(path))
    if not isinstance(name, str) or not name:
        errors.append("name 缺失")
    else:
        if not NAME_RE.match(name):
            bad = "".join(sorted(set(NON_NAME_CHARS.findall(name))))
            reason = f"含非法字符 {bad}" if bad else "不得以 - 开头或结尾，不得出现 --"
            errors.append(f"name 非法: {name}（{reason}）")
        if len(name) > MAX_NAME:
            errors.append(f"name 超过 {MAX_NAME} 字符: {len(name)}")
        if name != dirname:
            errors.append(f"name ({name}) 必须与目录名 ({dirname}) 一致")

    description = front.get("description")
    if not isinstance(description, str) or not description.strip():
        errors.append("description 缺失或为空")
    elif len(description) > MAX_DESCRIPTION:
        errors.append(f"description 超过 {MAX_DESCRIPTION} 字符: {len(description)}")

    compatibility = front.get("compatibility")
    if compatibility is not None:
        if not isinstance(compatibility, str) or not compatibility.strip():
            errors.append("compatibility 为空")
        elif len(compatibility) > MAX_COMPATIBILITY:
            errors.append(f"compatibility 超过 {MAX_COMPATIBILITY} 字符: {len(compatibility)}")

    metadata = front.get("metadata")
    if metadata is not None:
        if not isinstance(metadata, dict):
            errors.append("metadata 必须是 key-value 映射")
        else:
            for key, value in metadata.items():
                if isinstance(value, RawScalar):
                    errors.append(f"metadata.{key} 的值必须是字符串，请加引号（当前为 {value}）")
                elif not isinstance(value, str):
                    errors.append(f"metadata.{key} 的值必须是字符串")

    for key in front:
        if key not in KNOWN_KEYS:
            warnings.append(f"frontmatter 含非规范字段: {key}")

    lines = len(text.splitlines())
    if lines > MAX_SKILL_LINES:
        warnings.append(f"{SKILL_ENTRY} 共 {lines} 行，建议保持在 {MAX_SKILL_LINES} 行以内")

    for target in re.findall(r"\]\(([^)\s]+)\)", text):
        if target.startswith(("/", "#", "http", "<")):
            continue
        local = target.split("#")[0]
        if len(local.split("/")) > 2:
            warnings.append(f"引用层级过深（建议不超过一层）: {target}")

    return errors, warnings


def main(argv):
    roots = []
    for idx, arg in enumerate(argv):
        if arg == "--root" and idx + 1 < len(argv):
            roots.append(argv[idx + 1])
    if not roots:
        roots = ["skills", "ograc-skills"]
        roots += sorted(
            entry
            for entry in os.listdir(".")
            if os.path.isdir(entry)
            and entry not in roots
            and os.path.isfile(os.path.join(entry, SKILL_ENTRY))
        )

    skills = discover(roots)
    failed = 0
    warn_count = 0
    for path, listing in skills:
        errors, warnings = validate(path, listing)
        if errors:
            failed += 1
            print(f"FAIL  {path}")
            for message in errors:
                print(f"        - {message}")
        for message in warnings:
            warn_count += 1
            print(f"WARN  {path}: {message}")

    print(f"\n汇总: {len(skills)} 个 skill，{len(skills) - failed} 合规，{failed} 违规；{warn_count} 条警告")
    if failed:
        print("规范: https://github.com/agentskills/agentskills/blob/main/docs/specification.mdx")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
