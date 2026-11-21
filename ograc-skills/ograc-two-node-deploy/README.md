# ograc-two-node-deploy

oGRAC 两节点测试集群的构建、安装、启动与验证 skill。

- 入口：`SKILL.md`
- 适用：新代码部署、release with debug info 构建、停机刷新二进制、按顺序启动与排障。
- 环境参数：`NODE0`、`NODE1`、`ROOT`、`SRC`、`DATA_DEV`/`REDO_DEV`/`ARCH_DEV`/`GCC_DEV`；详见 `SKILL.md` 的“环境参数”。
- 脚本：`scripts/`；参考文档：`references/`；配置模板：`assets/`。

安全约定：只操作 `$ROOT` 下的本实例；禁止宽泛 `pkill`；停止/卸载/覆盖前先确认。
