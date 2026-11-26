# lib/ 第三方依赖

jar 不入库，按下表放置。`build.xml` 编译时用 `lib/**/*.jar` 作 classpath，`run/funcs.sh` 运行时的
classpath 也是按目录通配，**文件名不必与下表完全一致**。

| 目录 | 必需 | 文件 | 来源 |
|---|---|---|---|
| `lib/` | 是 | `log4j-1.2.17.jar` | <https://archive.apache.org/dist/logging/log4j/1.2.17/> |
| `lib/` | 否 | `apache-log4j-extras-1.1.jar` | 上游默认附带；源码未直接引用 |
| `lib/postgres/` | 是 | `opengauss-jdbc-<version>.jar`、`postgresql.jar` | Maven `org.opengauss:opengauss-jdbc` 或 <https://opengauss.org/zh/download/> |
| `lib/firebird/` | 否 | `jaybird-2.2.9.jar`、`connector-api-1.5.jar` | Jaybird 官方发布件 |
| `lib/oracle/` | 否 | `ojdbc*.jar`，或设置 `ORACLE_HOME` | Oracle 官方，见 `oracle/README.txt` |

驱动选择与构建步骤见 [`../BUILD.md`](../BUILD.md)。
`postgres/README_cn.md` 与 `postgres/README_en.md` 是 openGauss 官方 JDBC 说明（上游原文），保留作参考。
