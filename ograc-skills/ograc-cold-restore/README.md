# ograc-cold-restore

用 `dsscmd cp` 对 oGRAC 实例做停机一致的冷备和整实例恢复。

- 入口：`SKILL.md`
- 适用：数据基线备份、TPC-C 数据回滚、排查 ctrl 尺寸/DSS 假死/SCSI PR/UB pool 残留。
- 环境参数：`NODE0`、`NODE1`、`ROOT`、`DATA_DEV`/`REDO_DEV`/`ARCH_DEV`/`GCC_DEV`、`SUDO_PWD_FILE`；详见 `SKILL.md` 的“环境参数”。
- 脚本：`scripts/`，其中 `restore_instance_from_cold_backup.sh` 是一键编排入口。

安全约定：恢复会覆盖当前数据；PR 清理只在全部服务停止后执行；只操作本实例的进程和共享内存。
