"""openGauss 全量 / 增量敏感信息扫描，并写出四张归一化表。"""
import argparse
import hashlib
import json
import os
import re
import socket
import sqlite3
import subprocess
import sys
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path

SKILL_DIR = Path(__file__).resolve().parents[1]
RULES = SKILL_DIR / "rules" / "opengauss.toml"
DEFAULT_WORKDIR = Path(os.environ.get("OPENGAUSS_SCAN_WORKDIR", r"D:\orgscan\opengauss"))
DEFAULT_OUT = Path(
    os.environ.get(
        "OPENGAUSS_SCAN_REPORT",
        r"D:\Files\安全SE\社区安全\敏感信息扫描\opengauss-敏感信息扫描结果.md",
    )
)
TOOL_CANDIDATES = [
    os.environ.get("REPO_SECRET_SCAN", ""),
    r"D:\orgscan\repo_secret_scan",
    r"C:\Users\zhoucong\AppData\Local\Temp\repo_secret_scan",
]
TARGET_RULES = {
    "huawei-cloud-ak",
    "huawei-cloud-sk",
    "gitcode-gitee-token",
    "gitcode-gitee-url-token",
    "llm-sk-api-key",
    "openai-api-key",
}
NOISE_SK = re.compile(
    r"(?i)^sk-(?:migration-|snapshot-|pull-|delete-|spinner-|toggleable|"
    r"your-|proj-abcdefgh|secret-after-redaction|fixture-)"
)
PRIVATE_HOST = re.compile(
    r"\b(?:10|127)\.\d+\.\d+\.\d+\b|\b192\.168\.\d+\.\d+\b|"
    r"\b172\.(?:1[6-9]|2\d|3[0-1])\.\d+\.\d+\b"
)
WATERMARK_RE = re.compile(
    r"<!-- opengauss-scan-watermark\n(.*?)\n-->",
    re.S,
)
BUCKETS = (
    ("valid_official", "确认仍然有效，属于官方社区资源"),
    ("valid_other", "确认仍然有效、不属于官方社区资源"),
    ("invalid", "确认已失效"),
    ("unknown", "无法确认"),
)


def tool_root():
    for item in TOOL_CANDIDATES:
        if item and (Path(item) / "orgscan" / "__main__.py").is_file():
            return Path(item)
    raise SystemExit("找不到 repo_secret_scan。设置 REPO_SECRET_SCAN 或克隆到 D:/orgscan/repo_secret_scan")


def run(cmd, cwd=None, timeout=120, env=None):
    merged = os.environ.copy()
    merged["GIT_SSL_NO_VERIFY"] = "1"
    merged["PYTHONUTF8"] = "1"
    if env:
        merged.update(env)
    return subprocess.run(
        cmd,
        cwd=cwd,
        timeout=timeout,
        text=True,
        encoding="utf-8",
        errors="replace",
        capture_output=True,
        env=merged,
    )


def git(mirror, args, timeout=120):
    return run(["git", "-C", str(mirror), *args], timeout=timeout)


def connect():
    db = DEFAULT_WORKDIR / "orgscan.sqlite"
    if not db.is_file():
        raise SystemExit("台账不存在：%s" % db)
    conn = sqlite3.connect(db)
    conn.row_factory = sqlite3.Row
    return conn


def load_repos(conn):
    repos = {}
    for row in conn.execute("select id, full_name, default_branch, url, status from repo order by full_name"):
        repos[row["id"]] = dict(row)
    return repos


def load_findings(conn):
    rules = ",".join("?" for _ in TARGET_RULES)
    rows = list(conn.execute(
        "select * from finding where fork_id=0 and rule in (%s)" % rules,
        tuple(TARGET_RULES),
    ))
    rows.extend(conn.execute(
        """
        select * from finding
        where fork_id=0 and rule='generic-api-key'
          and (snippet like '%access_token%' or snippet like '%private_token%')
          and lower(path) not like '%calender.js' and lower(path) not like '%calendar.js'
        """
    ))
    return rows


def show_file(mirror, sha, path):
    if not sha or not path or not mirror.is_dir():
        return ""
    proc = git(mirror, ["show", "%s:%s" % (sha, path)], timeout=60)
    if proc.returncode != 0:
        return ""
    return proc.stdout or ""


def noise(row):
    secret = row["secret"] or ""
    rule = row["rule"] or ""
    path = (row["path"] or "").replace("\\", "/").lower()
    if rule in ("llm-sk-api-key", "openai-api-key") and NOISE_SK.search(secret):
        return True
    if rule == "aws-access-token" and any(part in path for part in ("blog", "dummy", "vitepress", "/post/")):
        return True
    if re.search(r"(?i)(your[_-]|placeholder|changeme|example)", secret):
        return True
    return False


def pair_resources(rows, repos):
    """同一密钥跨提交合并；同一路径上的 AK/SK 配成一条。"""
    by_secret = defaultdict(list)
    for row in rows:
        if noise(row):
            continue
        by_secret[row["secret"]].append(row)

    ak_rows = []
    sk_by_path = defaultdict(list)
    others = []
    for secret, group in by_secret.items():
        rule = group[0]["rule"]
        if rule == "huawei-cloud-ak":
            ak_rows.append((secret, group))
        elif rule == "huawei-cloud-sk":
            for row in group:
                sk_by_path[(row["repo_id"], row["path"])].append(secret)
        else:
            others.append((secret, group))

    resources = []
    used_sk = set()
    for ak, group in ak_rows:
        paths = {(row["repo_id"], row["path"]) for row in group}
        sk = ""
        for key in paths:
            for candidate in sk_by_path.get(key, []):
                sk = candidate
                used_sk.add(candidate)
                break
            if sk:
                break
        resources.append(make_resource("obs", ak, sk, group, repos))
    for secret, group in others:
        kind = "llm" if group[0]["rule"] in ("llm-sk-api-key", "openai-api-key") else "token"
        resources.append(make_resource(kind, secret, "", group, repos))
    return resources


def earliest(group):
    def key(row):
        return (row["date"] or "9999", row["commit_sha"] or "")
    return sorted(group, key=key)[0]


def make_resource(kind, secret, sk, group, repos):
    first = earliest(group)
    repo = repos[first["repo_id"]]
    authors = []
    for row in sorted(group, key=lambda item: item["date"] or "9999"):
        if row["author"] and row["author"] not in authors:
            authors.append(row["author"])
    repo_ids = sorted({row["repo_id"] for row in group})
    paths = sorted({(row["path"] or "").replace("\\", "/") for row in group})
    return {
        "kind": kind,
        "secret": secret,
        "sk": sk,
        "rule": first["rule"],
        "repo_id": first["repo_id"],
        "repo_ids": repo_ids,
        "full_name": repo["full_name"],
        "sha": first["commit_sha"],
        "path": first["path"],
        "paths": paths,
        "line": first["line"] or 0,
        "author": authors[0] if authors else "",
        "authors": authors,
        "date": first["date"] or "",
        "snippet": first["snippet"] or "",
    }


def official(resource, file_text):
    path = (resource["path"] or "").replace("\\", "/")
    name = resource["full_name"]
    if name.endswith("/infra") and "webrelease" in path:
        return True
    if "src/test/regress" in path and resource["kind"] == "obs":
        return True
    if "datavec/" in path and path.endswith(".md"):
        return True
    if "aifeature" in path.lower() or "AIFeatureGuide" in path or path.endswith("附录.md"):
        return True
    if "opengaussorg" in file_text or "enterprises/opengauss" in file_text:
        return True
    return False


def resource_name(resource, file_text):
    path = " ".join(resource.get("paths") or [resource["path"] or ""])
    if resource["kind"] == "obs" and "webrelease" in path:
        return "infra 镜像构建 OBS 密钥"
    if resource["kind"] == "obs" and "GNUmakefile_for_llt" in path:
        return "回归测试 OBS（gaussdbcheck）"
    if resource["kind"] == "obs":
        return "回归测试 OBS（gaussdb）"
    if path.endswith("deepseek.md"):
        return "datavec 文档 DeepSeek 默认密钥"
    if path.endswith("docling.md") or path.endswith("unstructured.md"):
        return "datavec 文档 Docling / Unstructured 默认密钥"
    if path.endswith("ragas.md"):
        return "datavec 文档 Ragas 默认密钥"
    if "aifeature" in path.lower() or path.endswith("附录.md"):
        return "AI 特性附录 access_token"
    if "CMakeLists.txt" in path:
        return "GitCode 克隆 URL 令牌"
    if "deploy.env" in path:
        return "oGMemory 部署环境 OpenAI 密钥"
    if "startup" in path.lower() or ".env.example" in path or "REDTEAM" in path:
        return "oGMemory 默认 OPENAI_API_KEY"
    if "deployment" in path and resource["kind"] == "llm":
        return "oGMemory 部署文档 LLM 密钥"
    if "Opengaussissuecollect.py" in path:
        return "Gitee opengaussorg issue 令牌"
    return "%s %s" % (resource["full_name"].split("/")[-1], resource["rule"])


def resource_type(resource, file_text):
    if resource["kind"] == "obs":
        return "华为云 OBS AK/SK"
    if resource["kind"] == "llm":
        return "大模型 API Key"
    if "gitee.com" in file_text and "gitcode.com" not in file_text:
        return "Gitee access_token"
    if "gitcode.com" in file_text and "gitee.com" not in file_text:
        return "GitCode access_token"
    return "Gitee/GitCode access_token"


def original_text(resource):
    if resource["sk"]:
        return "AK `%s` / SK `%s`" % (resource["secret"], resource["sk"])
    return "`%s`" % resource["secret"]


def commit_link(resource):
    return "https://gitcode.com/%s/commit/%s" % (resource["full_name"], resource["sha"])


def file_link(resource):
    line = "#L%s" % resource["line"] if resource["line"] else ""
    return "https://gitcode.com/%s/blob/%s/%s%s" % (
        resource["full_name"], resource["sha"], resource["path"], line
    )


def remediated(resource, repos):
    """当前默认分支文件里是否已经没有原文。"""
    hits = []
    mirrors = 0
    for repo_id in resource["repo_ids"]:
        repo = repos[repo_id]
        mirror = DEFAULT_WORKDIR / "mirrors" / ("r_%d.git" % repo_id)
        if not mirror.is_dir():
            continue
        mirrors += 1
        branch = repo["default_branch"] or "master"
        ref = "refs/heads/%s" % branch
        for needle in (resource["secret"], resource["sk"]):
            if not needle:
                continue
            proc = git(mirror, ["grep", "-I", "-n", "-F", needle, ref], timeout=60)
            if proc.returncode == 0 and proc.stdout.strip():
                chunks = proc.stdout.splitlines()[0].split(":")
                location = ":".join(chunks[1:3]) if len(chunks) >= 3 else chunks[-1]
                hits.append("%s %s" % (repo["full_name"].split("/")[-1], location))
                break
    if hits:
        return "否。仍在 " + "；".join(hits[:3])
    if not mirrors:
        return "无法确认。本地没有镜像"
    return "是。当前默认分支文件中已没有"


def cache_key(provider, secret):
    return hashlib.sha256((provider + "|" + secret).encode()).hexdigest()


def load_cache():
    path = DEFAULT_WORKDIR / "verify-cache.json"
    if not path.is_file():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}


def save_cache(cache):
    path = DEFAULT_WORKDIR / "verify-cache.json"
    path.write_text(json.dumps(cache, ensure_ascii=False, indent=1), encoding="utf-8")


def tcp_open(host):
    try:
        with socket.create_connection((host, 443), 3):
            return True
    except OSError:
        return False


def verify_resource(resource, file_text, cache, recheck):
    sys.path.insert(0, str(tool_root()))
    from orgscan.confirm.online import CHECKS  # noqa: WPS433

    class Cfg:
        timeout = 20

    class Item:
        pass

    def cached(provider, secret, caller):
        key = cache_key(provider, secret)
        if key in cache and not recheck:
            return cache[key]
        result = caller()
        cache[key] = result
        save_cache(cache)
        return result

    if resource["kind"] == "obs":
        endpoint = ""
        match = re.search(r"https://obs\.[a-z0-9-]+\.myhuaweicloud\.com", file_text)
        if match:
            endpoint = match.group(0)
        else:
            region = re.search(r"(?i)region\s*[:=]\s*['\"]?([a-z0-9-]+)", file_text)
            if region:
                endpoint = "https://obs.%s.myhuaweicloud.com" % region.group(1)
        private = []
        lines = file_text.splitlines()
        for index, line in enumerate(lines):
            if resource["secret"] in line or (resource["sk"] and resource["sk"] in line):
                window = "\n".join(lines[max(0, index - 5):index + 1])
                private = PRIVATE_HOST.findall(window)
                if private:
                    break
        item = Item()
        item.huawei_secret_key = resource["sk"]
        item.huawei_endpoint = endpoint
        result = cached(
            "huawei",
            resource["secret"] + "|" + resource["sk"] + "|" + endpoint,
            lambda: CHECKS["huawei"](resource["secret"], item, Cfg()),
        )
        if private and not tcp_open(private[-1]):
            return "unknown", "内网 %s 不可达。%s" % (private[-1], result.get("detail") or "")
        status = result.get("status") or "error"
        if status == "valid":
            return "valid", result.get("detail") or "有效"
        if status == "invalid":
            return "invalid", result.get("detail") or "无效"
        return "unknown", result.get("detail") or "无法确认"

    item = Item()
    if resource["kind"] == "llm":
        names = ("deepseek", "dashscope", "openai")
    else:
        names = ("gitee", "gitcode") if "gitcode.com" not in file_text or "gitee.com" in file_text else ("gitcode", "gitee")
    results = [
        cached(name, resource["secret"], lambda name=name: CHECKS[name](resource["secret"], item, Cfg()))
        for name in names
    ]
    if any(row.get("status") == "valid" for row in results):
        hit = next(row for row in results if row.get("status") == "valid")
        account = hit.get("account") or ""
        return "valid", "%s%s" % (hit.get("detail") or "有效", ("，账号 " + account) if account else "")
    if results and all(row.get("status") == "invalid" for row in results):
        return "invalid", "；".join(row.get("detail") or "" for row in results)
    if any(row.get("status") == "invalid" for row in results):
        return "invalid", "；".join(row.get("detail") or "" for row in results if row.get("status") == "invalid")
    return "unknown", "；".join((row.get("detail") or row.get("status") or "") for row in results)


def branch_tip(repo):
    mirror = DEFAULT_WORKDIR / "mirrors" / ("r_%d.git" % repo["id"])
    branch = repo["default_branch"] or "master"
    ref = "refs/heads/%s" % branch
    if not mirror.is_dir():
        return {"branch": branch, "end": "", "time": "", "count": 0, "error": "镜像缺失"}
    tip = git(mirror, ["rev-parse", ref], timeout=30)
    if tip.returncode != 0:
        return {"branch": branch, "end": "", "time": "", "count": 0, "error": "没有 " + ref}
    sha = (tip.stdout or "").strip()
    when = git(mirror, ["log", "-1", "--format=%cI", sha], timeout=30)
    count = git(mirror, ["rev-list", "--count", sha], timeout=300)
    return {
        "branch": branch,
        "end": sha,
        "time": (when.stdout or "").strip(),
        "count": int((count.stdout or "0").strip() or 0),
        "error": "",
    }


def collect_ranges(repos):
    ranges = {}
    with ThreadPoolExecutor(max_workers=6) as pool:
        future_map = {pool.submit(branch_tip, repo): repo for repo in repos.values()}
        for future in as_completed(future_map):
            repo = future_map[future]
            try:
                info = future.result()
            except Exception as exc:  # noqa: BLE001
                info = {"branch": repo["default_branch"], "end": "", "time": "", "count": 0, "error": str(exc)[:120]}
            info["added"] = info.get("count") or 0
            info["start"] = "历史根（全部可达提交）"
            ranges[repo["full_name"]] = info
    return ranges


def md_cell(text):
    return (text or "").replace("|", "\\|").replace("\n", " ")


def watermark_block(ranges, mode):
    payload = {
        "mode": mode,
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "repos": {
            name: {
                "default_branch": info.get("branch") or "",
                "end": info.get("end") or "",
                "added": info.get("added") or 0,
            }
            for name, info in sorted(ranges.items())
        },
    }
    return "<!-- opengauss-scan-watermark\n%s\n-->" % json.dumps(payload, ensure_ascii=False, indent=1)


def parse_watermark(text):
    match = WATERMARK_RE.search(text)
    if not match:
        raise SystemExit("报告里没有扫描水位。先运行 full。")
    return json.loads(match.group(1))


def write_report(path, resources, ranges, mode):
    lines = [
        "# openGauss 组织敏感信息扫描结果",
        "",
        "扫描范围：https://gitcode.com/opengauss 公开主仓。工具：https://gitcode.com/CCCHHHMMM/repo_secret_scan 。未扫外部 fork。",
        "同一密钥跨提交、跨仓库合并为一行。在线核验只做只读身份或 ListBuckets。",
        "本文件含密钥原文，只留本地，不要外发。",
        "",
        "模式：%s。提交数是默认分支可达提交；旁路 ref 已纳入扫描，但不单独记成一个终点。" % ("全量" if mode == "full" else "增量"),
        "",
        watermark_block(ranges, mode),
        "",
        "## 扫描 commit 范围",
        "",
        "| 仓库 | 默认分支 | 扫描起点 | 扫描终点 | 默认分支提交数 | 本次新增 |",
        "|---|---|---|---|---|---|",
    ]
    for name in sorted(ranges):
        info = ranges[name]
        end = info.get("end") or info.get("error") or ""
        if info.get("time"):
            end = "%s %s" % (info["end"], info["time"])
        lines.append("| %s | %s | %s | %s | %s | %s |" % (
            md_cell(name),
            md_cell(info.get("branch") or ""),
            md_cell(info.get("start") or ""),
            md_cell(end),
            info.get("count") or 0,
            info.get("added") if info.get("added") is not None else 0,
        ))
    grouped = defaultdict(list)
    for resource in resources:
        grouped[resource["bucket"]].append(resource)
    for key, title in BUCKETS:
        lines.extend(["", "## %s" % title, ""])
        lines.append("| 敏感信息名称 | 敏感信息类型 | commit链接 | 敏感信息原文 | 敏感信息文件链接 | 合入者id | 是否有效 | 最近代码分支是否已整改 |")
        lines.append("|---|---|---|---|---|---|---|---|")
        rows = grouped.get(key) or []
        if not rows:
            lines.append("| 无 | | | | | | | |")
            continue
        for resource in rows:
            lines.append("| %s | %s | %s | %s | %s | %s | %s | %s |" % (
                md_cell(resource["name"]),
                md_cell(resource["type"]),
                md_cell(resource["commit_url"]),
                md_cell(resource["original"]),
                md_cell(resource["file_url"]),
                md_cell(resource["author"]),
                md_cell(resource["validity"]),
                md_cell(resource["fixed"]),
            ))
    lines.append("")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines), encoding="utf-8")


def build_resources(conn, recheck, skip_online):
    repos = load_repos(conn)
    resources = pair_resources(load_findings(conn), repos)
    cache = load_cache()
    built = []
    for index, resource in enumerate(resources, 1):
        mirror = DEFAULT_WORKDIR / "mirrors" / ("r_%d.git" % resource["repo_id"])
        file_text = show_file(mirror, resource["sha"], resource["path"])
        resource["name"] = resource_name(resource, file_text)
        resource["type"] = resource_type(resource, file_text)
        resource["original"] = original_text(resource)
        resource["commit_url"] = commit_link(resource)
        resource["file_url"] = file_link(resource)
        resource["fixed"] = remediated(resource, repos)
        is_official = official(resource, file_text)
        if skip_online:
            status, detail = "unknown", "未做在线核验"
        else:
            print("核验 %d/%d %s" % (index, len(resources), resource["name"]), flush=True)
            status, detail = verify_resource(resource, file_text, cache, recheck)
        resource["status"] = status
        if status == "valid" and is_official:
            resource["bucket"] = "valid_official"
            resource["validity"] = "有效。%s" % detail
        elif status == "valid":
            resource["bucket"] = "valid_other"
            resource["validity"] = "有效。%s" % detail
        elif status == "invalid":
            resource["bucket"] = "invalid"
            resource["validity"] = "无效。%s" % detail
        else:
            resource["bucket"] = "unknown"
            resource["validity"] = "无法确认。%s" % detail
        built.append(resource)
    return repos, built


def ancestor(mirror, parent, child):
    proc = git(mirror, ["merge-base", "--is-ancestor", parent, child], timeout=30)
    return proc.returncode == 0


def gitleaks_bin():
    bundled = tool_root() / "orgscan" / "bin" / "gitleaks.exe"
    if bundled.is_file():
        return str(bundled)
    return "gitleaks"


def gitleaks_range(mirror, start, end):
    gitleaks = gitleaks_bin()
    report = DEFAULT_WORKDIR / "tmp" / ("delta-%s.json" % hashlib.sha256(end.encode()).hexdigest()[:12])
    report.parent.mkdir(parents=True, exist_ok=True)
    if report.exists():
        report.unlink()
    proc = run([
        gitleaks, "git", str(mirror),
        "--log-opts", "%s..%s" % (start, end),
        "--config", str(RULES),
        "--report-format", "json",
        "--report-path", str(report),
        "--no-banner",
        "--exit-code", "0",
        "--max-target-megabytes", "50",
    ], timeout=600)
    if proc.returncode != 0:
        raise SystemExit(proc.stderr[-400:] or proc.stdout[-400:])
    if not report.is_file():
        return []
    try:
        data = json.loads(report.read_text(encoding="utf-8") or "[]")
    except json.JSONDecodeError:
        return []
    return data if isinstance(data, list) else []


def import_gitleaks(conn, repo_id, hits):
    sys.path.insert(0, str(tool_root()))
    from orgscan.db import Store  # noqa: WPS433
    store = Store(DEFAULT_WORKDIR / "orgscan.sqlite")
    try:
        for hit in hits:
            store.add_finding(
                repo_id, 0,
                hit.get("Commit") or "",
                hit.get("File") or "",
                hit.get("StartLine") or 0,
                hit.get("RuleID") or "",
                "gitleaks",
                hit.get("Secret") or "",
                hit.get("Match") or "",
                hit.get("Author") or "",
                hit.get("Email") or "",
                hit.get("Date") or "",
            )
    finally:
        store.close()
    conn.commit()


def scan_delta(conn, repo, start, end):
    mirror = DEFAULT_WORKDIR / "mirrors" / ("r_%d.git" % repo["id"])
    if not start or not end or start == end:
        return 0, 0
    if not ancestor(mirror, start, end):
        print("%s 的旧终点不是新终点的祖先，改为交给 orgscan 按 ref 差额扫描" % repo["full_name"])
        orgscan_scan([repo["full_name"]])
        return -1, -1
    commits = git(mirror, ["rev-list", "--count", "%s..%s" % (start, end)], timeout=120)
    count = int((commits.stdout or "0").strip() or 0)
    hits = gitleaks_range(mirror, start, end) if count else []
    import_gitleaks(conn, repo["id"], hits)
    print("%s 新增提交 %d，gitleaks 命中 %d" % (repo["full_name"], count, len(hits)))
    return count, len(hits)


def orgscan_scan(repos):
    root = tool_root()
    cmd = [
        sys.executable, "-m", "orgscan", "scan",
        "--org", "opengauss",
        "--workdir", str(DEFAULT_WORKDIR),
        "--no-forks",
        "--no-exclude-binary",
        "--all-refs",
        "--engines", "gitleaks",
        "--rules", str(RULES),
    ]
    if repos:
        cmd.extend(["--repos", ",".join(repos)])
    print("运行", " ".join(cmd), flush=True)
    proc = run(cmd, cwd=root, timeout=7200)
    sys.stdout.write(proc.stdout[-2000:])
    sys.stderr.write(proc.stderr[-2000:])
    if proc.returncode != 0:
        raise SystemExit("orgscan scan 退出 %s" % proc.returncode)


def apply_ranges(repos, previous, only, since_parent, do_fetch):
    ranges = {}
    conn = connect()
    try:
        for repo in repos.values():
            name = repo["full_name"]
            if only and name not in only:
                old = (previous or {}).get(name) or {}
                ranges[name] = {
                    "branch": old.get("default_branch") or repo["default_branch"],
                    "end": old.get("end") or "",
                    "time": "",
                    "count": 0,
                    "added": 0,
                    "start": old.get("end") or "",
                    "error": "",
                }
                continue
            if do_fetch:
                mirror = DEFAULT_WORKDIR / "mirrors" / ("r_%d.git" % repo["id"])
                branch = repo["default_branch"] or "master"
                if mirror.is_dir():
                    git(mirror, ["fetch", "--no-tags", "origin", "+refs/heads/%s:refs/heads/%s" % (branch, branch)], timeout=600)
            info = branch_tip(repo)
            old_end = ((previous or {}).get(name) or {}).get("end") or ""
            start = old_end
            if since_parent and (not only or name in only) and info.get("end"):
                mirror = DEFAULT_WORKDIR / "mirrors" / ("r_%d.git" % repo["id"])
                parent = git(mirror, ["rev-parse", "%s~%d" % (info["end"], since_parent)], timeout=30)
                if parent.returncode == 0:
                    start = (parent.stdout or "").strip()
            added, _hits = scan_delta(conn, repo, start, info.get("end") or "")
            info["start"] = "历史根（全部可达提交）"
            info["added"] = 0 if added < 0 else added
            ranges[name] = info
    finally:
        conn.close()
    return ranges


def prepare(args):
    global DEFAULT_WORKDIR
    if args.workdir:
        DEFAULT_WORKDIR = Path(args.workdir)
    conn = connect()
    try:
        repos, resources = build_resources(conn, args.recheck, args.no_online)
    finally:
        conn.close()
    return repos, resources


def cmd_full(args):
    if not args.from_ledger:
        root = tool_root()
        enumerate = [
            sys.executable, "-m", "orgscan", "enumerate",
            "--org", "opengauss", "--workdir", str(DEFAULT_WORKDIR), "--no-forks",
        ]
        proc = run(enumerate, cwd=root, timeout=900)
        print(proc.stdout[-500:])
        if proc.returncode != 0:
            raise SystemExit(proc.stderr[-500:])
        pending = connect()
        try:
            pending.execute("update repo set status='pending'")
            pending.commit()
        finally:
            pending.close()
        orgscan_scan([])
    repos, resources = prepare(args)
    ranges = collect_ranges(repos)
    out = Path(args.out)
    write_report(out, resources, ranges, "full")
    print("写入 %s ，资源 %d，仓库 %d" % (out, len(resources), len(ranges)))


def cmd_incremental(args):
    report = Path(args.out)
    if not report.is_file():
        raise SystemExit("找不到报告：%s" % report)
    watermark = parse_watermark(report.read_text(encoding="utf-8"))
    previous = watermark.get("repos") or {}
    conn = connect()
    try:
        repos = load_repos(conn)
    finally:
        conn.close()
    only = set(args.only.split(",")) if args.only else set()
    ranges = apply_ranges(repos, previous, only, args.since_parent, not args.no_fetch)
    # 未点名的仓库保持原终点，避免 --only 把其它仓库的终点抹掉
    for name, old in previous.items():
        if name not in ranges or (only and name not in only):
            ranges[name] = {
                "branch": old.get("default_branch") or "",
                "end": old.get("end") or "",
                "time": "",
                "count": 0,
                "added": 0,
                "start": old.get("end") or "",
                "error": "",
            }
    repos, resources = prepare(args)
    write_report(report, resources, ranges, "incremental")
    added = sum(info.get("added") or 0 for info in ranges.values())
    print("增量完成，新增提交 %d，写入 %s" % (added, report))


def main():
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    parser = argparse.ArgumentParser(description="扫描 openGauss 敏感信息并写出报告")
    parser.add_argument("mode", choices=("full", "incremental"))
    parser.add_argument("--workdir", default="")
    parser.add_argument("--out", default=str(DEFAULT_OUT))
    parser.add_argument("--from-ledger", action="store_true", help="不重新调用 orgscan，直接用现有台账")
    parser.add_argument("--no-online", action="store_true")
    parser.add_argument("--recheck", action="store_true")
    parser.add_argument("--no-fetch", action="store_true")
    parser.add_argument("--only", default="", help="只增量扫描这些 owner/repo，逗号分隔")
    parser.add_argument("--since-parent", type=int, default=0, help="验证用：起点改为终点往前 N 个提交")
    args = parser.parse_args()
    if args.workdir:
        global DEFAULT_WORKDIR
        DEFAULT_WORKDIR = Path(args.workdir)
    if args.mode == "full":
        cmd_full(args)
    else:
        cmd_incremental(args)


if __name__ == "__main__":
    main()
