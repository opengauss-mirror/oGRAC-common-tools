#!/usr/bin/env bash
# 仓库质量门禁。
#
# 用法: ci/check_repo.sh [--quick]
#   默认: 全部检查 —— shell/Python 语法、README 索引、明文密钥、skill 规范（agentskills + oGRAC 命名 + 扁平摆放）、Markdown 断链、LFS 指针、可执行位。
#   --quick: 只跑语法、索引、密钥四项，用于本地快速回路。
# 整改项与责任人见 docs/migration-map.md。
set -uo pipefail

usage() { sed -n '3,6p' "$0" | sed 's/^# \{0,1\}//'; }

strict=1
while [ $# -gt 0 ]; do
    case "$1" in
        --strict) strict=1; shift ;;
        --quick) strict=0; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "未知参数: $1" >&2; usage >&2; exit 2 ;;
    esac
done

root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "不在 git 仓库内" >&2; exit 2; }
cd "$root" || exit 2

pass=0
fail=0
failed_names=()

run_check() {
    local name=$1 out
    shift
    if out=$("$@" 2>&1); then
        printf '  \033[32mPASS\033[0m %s\n' "$name"
        pass=$((pass + 1))
    else
        printf '  \033[31mFAIL\033[0m %s\n' "$name"
        fail=$((fail + 1))
        failed_names+=("$name")
        [ -n "$out" ] && printf '%s\n' "$out" | head -20 | sed 's/^/         /'
    fi
}

tracked() { git -c core.quotepath=false ls-files --cached --others --exclude-standard -- "$@"; }

check_shell() {
    local f rc=0 err
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        if ! err=$(bash -n "$f" 2>&1); then
            printf '%s\n' "$err"
            rc=1
        fi
    done < <(tracked '*.sh')
    return $rc
}

check_python() {
    local f rc=0
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        case "$f" in vendor/benchmarksql_ograc/*) continue ;; esac   # 上游 py2 脚本，见 migration-map R11
        if ! python3 -c 'import sys; compile(open(sys.argv[1], encoding="utf-8").read(), sys.argv[1], "exec")' "$f" 2>/dev/null; then
            printf 'Python 3 语法错误: %s\n' "$f"
            rc=1
        fi
    done < <(tracked '*.py')
    return $rc
}

check_readme_index() {
    local rc=0 d
    if [ ! -f README.md ]; then
        echo "缺少 README.md"
        return 1
    fi
    for d in $(tracked | awk -F/ 'NF > 1 { print $1 }' | sort -u); do
        if ! grep -q -- "$d" README.md; then
            printf 'README.md 未收录目录: %s/\n' "$d"
            rc=1
        fi
    done
    return $rc
}

# 上游示例 props 的演示默认凭据（Firebird 的 PWbmsql、Oracle 的 scott/tiger），非真实泄露
is_secret_allowlisted() {
    case "$1" in
        vendor/benchmarksql_ograc/run/props.fb) return 0 ;;
        vendor/benchmarksql_ograc/run/props.ora) return 0 ;;
    esac
    return 1
}

LITERAL_PAT='^[[:space:]]*password[[:space:]]*=[[:space:]]*[A-Za-z0-9][A-Za-z0-9@#$%^&*!_.+-]{5,}|jdbc:[a-zA-Z]+://([0-9]{1,3}\.){3}[0-9]{1,3}|(assword|passphrase|pass phrase|sys_pwd)[^\n]*send[[:space:]]+"[^"$]'

check_secrets() {
    local rc=0 f hit
    local pat='AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|(^|[^A-Za-z0-9])(sk|ghp|glpat|xox[baprs])-[A-Za-z0-9_-]{20,}|password[[:space:]]*=[[:space:]]*["'"'"'][^"'"'"'$]{6,}["'"'"']'
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        if is_secret_allowlisted "$f"; then continue; fi
        if hit=$(grep -nEI -- "$pat" "$f" 2>/dev/null) || hit=$(grep -nEI -- "$LITERAL_PAT" "$f" 2>/dev/null); then
            printf '%s: %s\n' "$f" "$(printf '%s' "$hit" | head -2)"
            rc=1
        fi
    done < <(tracked)
    return $rc
}

check_skills() {
    python3 ci/check_skills.py
}

check_layout() {
    python3 ci/check_layout.py
}

check_markdown_links() {
    python3 ci/check_links.py
}

check_lfs_pointers() {
    local rc=0 f size count=0
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        size=$(wc -c <"$f" 2>/dev/null) || continue
        if [ "$size" -lt 200 ] && head -c 20 "$f" 2>/dev/null | grep -q 'version https'; then
            count=$((count + 1))
            [ "$count" -le 10 ] && printf '未展开的 LFS 指针: %s (%s 字节)\n' "$f" "$size"
            rc=1
        fi
    done < <(tracked)
    [ "$count" -gt 10 ] && printf '...共 %d 个未展开的 LFS 指针\n' "$count"
    return $rc
}

check_exec_bits() {
    local rc=0 mode f
    while IFS=$'\t' read -r mode f; do
        [ -n "$f" ] || continue
        if [ "$mode" != "100755" ]; then
            printf '可执行脚本缺 x 位: %s (%s)\n' "$f" "$mode"
            rc=1
        fi
    done < <(git ls-files -s '*.sh' | awk '{ print $1 "\t" $4 }')
    return $rc
}

printf '仓库自检（%s）\n' "$([ "$strict" -eq 1 ] && echo full || echo quick)"
run_check "shell 语法 (bash -n)" check_shell
run_check "Python 3 语法" check_python
run_check "README 目录索引完整性" check_readme_index
run_check "明文密钥扫描" check_secrets

if [ "$strict" -eq 1 ]; then
    run_check "skill 规范（规范/命名/摆放）" check_skills
    run_check "文件归位（PR 指引）" check_layout
    run_check "Markdown 链接" check_markdown_links
    run_check "LFS 指针已展开" check_lfs_pointers
    run_check "脚本可执行位" check_exec_bits
fi

printf '\n结果: %d 通过, %d 失败\n' "$pass" "$fail"
if [ "$fail" -gt 0 ]; then
    if [ "${#failed_names[@]}" -gt 0 ]; then
        printf '失败项: %s\n' "${failed_names[*]}"
    fi
    exit 1
fi
exit 0
