# 构建兼容修改说明

某些测试环境需要用系统 gcc 构建 binarylibs 的 oGRAC，并对 release 包做“保留调试符号”。这些修改是工作树的一部分，不属于上游代码；换分支、rebase 或重新 clone 后可能丢失，构建前可用 `scripts/preflight.sh` 检查。

> 这些适配不是所有环境都需要。`preflight.sh` 默认只把它们报为 `[WARN]`；如果你的部署依赖它们，设置 `STRICT_LOCAL_PATCHES=1` 让缺失变成 `[FAIL]`。

## 1. 保留调试符号（KEEP_DEBUG_INFO）

目的：官方 `release` 构建会执行 `func_release_symbol`，把二进制 strip 后单独打符号包。测试需要 release 优化 + 内嵌 DWARF，因此增加环境变量开关：

```bash
KEEP_DEBUG_INFO=1 sh build_ograc.sh release --with-dss
```

涉及文件与位置：

### build/Makefile.sh

`func_make_release()` 和 `func_making_package()` 的 release 分支中，将原来的：

```bash
func_release_symbol
```

改为：

```bash
if [[ "${KEEP_DEBUG_INFO:-0}" != "1" ]]; then
    func_release_symbol
else
    echo "KEEP_DEBUG_INFO=1: keep debug info in release binaries, skip symbol separation."
fi
```

### build/build_ograc.sh

统一符号包只在不保留调试信息时生成：

```bash
if [[ ${BUILD_TYPE} == "release" ]] && [[ "${KEEP_DEBUG_INFO:-0}" != "1" ]]; then
```

### build/build_dss.sh

DSS 的符号分离循环包在条件里；`KEEP_DEBUG_INFO=1` 时只创建空的 `dss_symbols/{bin,lib}`，不执行 `objcopy --strip-*`。

完整 diff 见 `assets/patches/build-system.patch`。

## 2. CBB/DSS 源码树不是 Git 仓库

`build_dss.sh` 原本要求 `CBB/`、`DSS/` 是 Git work tree，否则退出。若你的源码树是普通目录（例如从发布包解压），可放宽为：

```bash
elif [[ -d "${repo_path}" ]]; then
    echo "Reuse existing ${repo_name} source tree without .git: ${repo_path}"
```

`source_state()` 对非 Git 目录回退到 `files_state()`。

## 3. 第三方 gcc 工具链不可用时回退系统 gcc

第三方 binarylibs 中的 gcc 工具链可能不完整（例如符号链接指向构建机上不存在的路径）。处理方式：检查 `${THIRD_PATH}/buildtools/<gcc>/gcc/bin/gcc` 与 `g++` 是否可执行；不可执行时回退系统编译器：

```bash
export CC=$(command -v gcc)
export CXX=$(command -v g++)
export cc="${CC}"
export GCCFOLDER=""
export PATH=$(dirname "${CC}"):${PATH}
```

`write_dss_build_info()` 中 `third_party_gcc` 也做同样回退：

```bash
[[ -x "${third_party_gcc}" ]] || third_party_gcc=$(command -v gcc)
```

### CBB/build/linux/opengauss/build.sh

```bash
if [[ -x "$GCC_PATH/gcc/bin/gcc" && -x "$GCC_PATH/gcc/bin/g++" ]]; then
    export CC=$GCC_PATH/gcc/bin/gcc
    export CXX=$GCC_PATH/gcc/bin/g++
    ...
else
    echo "Warning: third-party gcc$gcc_version toolchain is incomplete; using system gcc/g++."
    export CC=$(command -v gcc)
    export CXX=$(command -v g++)
fi
```

## 4. 新版本 gcc 告警按错误处理

上游 CMake 同时使用 `-Werror`。较新的系统 gcc 对部分旧代码产生新告警，因此可在 `-Werror` 之后追加：

```cmake
add_compile_options(-Wno-error)
```

位置：

- `CBB/CMakeLists.txt`（在 `add_compile_options(-Werror)` 之后）
- `DSS/CMakeLists.txt`（在 `add_compile_options(-Werror)` 之后）

这是“只降级告警、不改变优化级别”的折中；不要删除 `-Werror` 本身。

## 5. UB 区域名与权限（部署环境适配）

若两节点同名用户的 UID 不一致，node0 以 `0600` 创建的 UB 段 node1 可能无法访问。常见适配是三处命名空间隔离 + 权限放宽：

- `pkg/src/cluster/dtc_remote_buffer.c`
  - `shm_pool_%d` → `shm_pool_vN_%d`（N 为隔离代次）
  - `ubsmem_shmem_allocate(..., 0600, ...)` → `0666`
- `pkg/src/protocol/cs_ub.c`
  - `ub_create_shm_region` / `ub_delete_shm_region` 同步使用相同区域名
- `pkg/src/cluster/dtc_ub_reclaim.c`
  - 对象名前缀 `%s_data_buf_part_%u` → `%s_vN_data_buf_part_%u`

注意：

1. `vN` 是部署时的隔离命名，避免与历史残留对象冲突；不是上游协议版本。全集群必须使用同一代次。
2. 这些文件里可能同时存在当前分支的其他改动，**不要用整文件覆盖的方式恢复**，只按标记做局部修改。
3. 修改后必须重新构建 `ogracd` 和全部 `output/lib/*.so`，并同时刷新两节点，否则会出现 502/503。
4. 更推荐的做法是让两节点的部署用户 UID/GID 一致，而不是长期依赖 `0666`。

## 6. 构建前检查清单

```bash
grep -n KEEP_DEBUG_INFO build/Makefile.sh build/build_ograc.sh build/build_dss.sh
grep -n 'using system gcc' build/build_dss.sh CBB/build/linux/opengauss/build.sh
grep -n 'Wno-error' CBB/CMakeLists.txt DSS/CMakeLists.txt
grep -n 'shm_pool_v' pkg/src/cluster/dtc_remote_buffer.c pkg/src/protocol/cs_ub.c
grep -n '_v[0-9]*_data_buf_part_' pkg/src/cluster/dtc_ub_reclaim.c
```

`scripts/preflight.sh` 已包含以上检查（默认非致命）。
