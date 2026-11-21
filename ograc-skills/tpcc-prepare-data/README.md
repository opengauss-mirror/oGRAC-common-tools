# tpcc-prepare-data

为 oGRAC 集群准备 TPC-C 测试数据（默认 100 仓）。

- 入口：`SKILL.md`
- 适用：首次导入、重建 TPCC 数据、为新代码测试准备压测基线。
- 环境参数：`NODE0`/`CONN`、`DB_PORT`、`DB_USER`、`BENCH`、`ROOT`；详见 `SKILL.md` 的“环境参数”。
- 脚本：`scripts/load_tpcc.sh`（导入）、`scripts/verify_tpcc.sh`（行数校验）。

安全约定：只操作 `TPCC` schema；`--recreate` 前确认；密码只通过环境变量或 props 传递，props 权限 600。
