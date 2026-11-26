# 构建与运行指南

BenchmarkSQL 5.0 的 oGRAC 分支。仓库只保留源码，jar 与构建产物需本地准备。

## 1. 依赖

| 依赖 | 版本 | 用途 |
|---|---|---|
| JDK | 8（上游要求 7+，openGauss JDBC 要求 1.8） | 编译与运行 |
| Apache Ant | 1.9+ | 构建；没有 Ant 见第 3.2 节手工编译 |
| openGauss JDBC | 与集群版本匹配，如 7.0.0 | 连接 oGRAC |
| log4j | 1.2.17 | 源码 `import org.apache.log4j.*` 必需 |
| numactl | 可选 | `runBenchmark.sh` 绑核用，非必需 |

## 2. 准备 jar

jar 不入库，按下面的来源放到 `lib/` 对应子目录（文件名不必完全一致，`build.xml` 与 `funcs.sh` 都是按目录通配）。

### 2.1 openGauss JDBC → `lib/postgres/`

两种方式任选：

- **Maven 中央仓库**：`org.opengauss:opengauss-jdbc:<version>`
- **官网下载**：<https://opengauss.org/zh/download/> → openGauss Connectors → JDBC，解压后得到
  `opengauss-jdbc-<version>.jar` 与 `postgresql.jar`，两个都放进去。

细节与校验方法见 [`../lib/postgres/README_cn.md`](lib/postgres/README_cn.md)。

### 2.2 log4j → `lib/`

`log4j-1.2.17.jar`，来自 Apache 归档：<https://archive.apache.org/dist/logging/log4j/1.2.17/>。

> log4j 1.x 已停止维护且有已知漏洞，仅限隔离测试环境。长期使用建议评估 log4j 2 的 1.x 兼容桥。

上游默认还带 `apache-log4j-extras-1.1.jar`，本分支源码未直接引用，编译报错时再加。

### 2.3 可选：Firebird / Oracle

`lib/firebird/`（`jaybird-2.2.9.jar`、`connector-api-1.5.jar`）与 `lib/oracle/`（`ojdbc*.jar`，
或设置 `ORACLE_HOME`）只在对应 `db=` 下需要，oGRAC 压测不用。

## 3. 构建

### 3.1 用 Ant（推荐）

```bash
cd vendor/benchmarksql_ograc
ant              # 默认 target = dist
ls -l dist/BenchmarkSQL-5.0.jar
```

`build.xml` 的 `compile` 用 `lib/**/*.jar` 作 classpath，`dist` 把 `build/` 打成
`dist/BenchmarkSQL-5.0.jar`。`build/` 与 `dist/` 已被 `.gitignore` 忽略，不要提交。

### 3.2 手工编译（没有 Ant 时）

```bash
cd vendor/benchmarksql_ograc
mkdir -p build dist
javac -encoding UTF-8 -source 8 -target 8 -Xlint:all \
      -cp "lib/log4j-1.2.17.jar" \
      -d build $(find src -name '*.java')
jar cf dist/BenchmarkSQL-5.0.jar -C build .
```

源码只引用 `org.apache.log4j.*`，JDBC 驱动是运行时按类名加载的，编译期不需要放进 classpath。

## 4. 编译自检

```bash
cd run
source funcs.sh ograc_run.og      # 需要先填好 ograc_run.og 的地址与口令
setCP
java -cp "$myCP" ExecJDBC -d "select 1"
```

`setCP` 依据 `db=` 选 classpath：`postgres` → `../lib/postgres/*:../lib/*:../dist/*`，
oGRAC 走这条分支，所以 `db=postgres` 不要改。

## 5. 装载数据

```bash
cd run
./runDatabaseBuild.sh ograc_run.og
```

顺序为 `tableCreates_par` → `runLoader.sh` → `indexCreates_par` + `buildFinish`（见脚本）。
需要重建时先 `./runDatabaseDestroy.sh ograc_run.og`，再重新 build。

## 6. 运行压测

```bash
cd run
./runBenchmark.sh ograc_run.og
```

若机器不是 320 核的鲲鹏机型，脚本里的 `numactl -C 160-239,240-319` 会直接失败。绕开方式：

```bash
cd run
java -cp ".:../lib/postgres/*:../lib/*:../dist/*" -Dprop=ograc_run.og jTPCC
```

结果目录与 `run/logs/` 由脚本自行创建，均已忽略入库。

## 7. props 关键字段

| 字段 | 说明 |
|---|---|
| `db` | 固定 `postgres`，决定 classpath 分支 |
| `driver` | 用官网 `postgresql.jar` 时填 `org.postgresql.Driver`；只用 `opengauss-jdbc-*.jar` 时填 `org.opengauss.Driver` |
| `conn` | oGRAC 示例为 `jdbc:oGRAC://<node0_ip>:<port>` |
| `nodeId` / `nodeCnt` | 本分支新增。多节点压测时按节点编号填，保证各节点使用的 warehouse 不重叠 |
| `warehouses` | **必须能被 `nodeCnt` 整除**，否则 `jTPCC` 直接报错退出 |
| `terminals` / `runMins` | 压测并发与时长；`runTxnsPerTerminal` 与 `runMins` 二者只能一个非 0 |

## 8. 已知问题

- `run/runBenchmark.sh`、`runLoader.sh`、`runSQL.sh` 里写死了 `/usr/bin/java`；JDK 不在该路径时需改脚本或按第 6 节用 `java` 直接调用。
- `runBenchmark.sh` 绑核参数与机型绑定（`160-239,240-319`），见第 6 节。
- `run/misc/os_collector_linux.py` 是上游的 **Python 2** 脚本，Python 3 下语法错误；未在使用可不理会。
- `run/props.proxy`、`run/props.sharding` 是通用示例，`driver` 与实际驱动版本可能不匹配，按第 7 节调整。
