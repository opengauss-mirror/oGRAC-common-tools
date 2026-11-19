# ograc-process-fault-longrun

oGRAC 进程故障长稳测试流水线（只定位、记录，不修复）。

- 入口：`SKILL.md`
- 适用：用最新二进制持续验证进程 SIGKILL 后的 GBP/DRC/DLS 恢复。
- 环境参数：`NODE0`、`NODE1`、`ROOT`、`PIPE`、`BASE_BACKUP`、`MAX_ROUNDS`；详见 `SKILL.md` 的“环境参数”。
- 外部依赖：`$PIPE/scripts/` 下的 controller、check、restore 脚本（契约见 `SKILL.md`）。
- 脚本：`scripts/run_long_stability.sh`（驱动）、`scripts/collect_failure.sh`（取证）。

安全约定：长稳期间禁止改代码/重建/部署；kill 必须限定到本实例；gdb 采集有界。
