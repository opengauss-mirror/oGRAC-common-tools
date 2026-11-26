# common-scripts

会话外使用的运维脚本。目标位置为 `tools/`，迁移前保持现有路径不变。

## ograc_sim_single.sh

单文件创建 oGRAC 单集群 LUN 开发环境（4 个 LUN，每个 LUN 两条 loopback 路径）。脚本内嵌 Dockerfile 与 CMS `cluster.sh`，不依赖 `docker/lun-sim/` 下的其他文件，复制到 oGRAC 源码树任意目录即可运行。

前置条件：

- 宿主机安装 Docker，并支持 LIO/configfs、`tcm_loop`、`sg3_utils`。
- oGRAC 源码树包含 `build/build_ograc.sh`；编译还需要三方库，默认搜索源码根目录及 `third_party/`，也可设置 `THIRD_PARTY_PATH`。
- `install` 需要 `package/oGRAC-*.tgz` 部署包；已有合适部署包时可跳过 `make`。

```bash
cp common-scripts/ograc_sim_single.sh /path/to/oGRAC/
cd /path/to/oGRAC

sudo bash ./ograc_sim_single.sh create         # 创建 LUN、镜像和容器
sudo bash ./ograc_sim_single.sh init           # 安装容器内编译依赖
sudo bash ./ograc_sim_single.sh make debug     # 编译（已有部署包时可跳过）
sudo bash ./ograc_sim_single.sh install debug  # 安装双节点
sudo bash ./ograc_sim_single.sh start
sudo bash ./ograc_sim_single.sh verify
```

常用命令：

```bash
sudo bash ./ograc_sim_single.sh status
sudo bash ./ograc_sim_single.sh sql 0 "SELECT OPEN_STATUS FROM DV_DATABASE;"
sudo bash ./ograc_sim_single.sh login 0
sudo bash ./ograc_sim_single.sh stop
sudo bash ./ograc_sim_single.sh restart
sudo bash ./ograc_sim_single.sh log 100
sudo bash ./ograc_sim_single.sh destroy
```

默认环境目录为 `/home/<用户>/ogracsim_single/cluster`，容器名为 `ograc-dev-<用户>`，默认端口为 CMS `18520/18521`、DSS `19100/19101`、oGRAC `19300/19301`。

已知整改项：默认库口令硬编码在脚本内，需改为环境变量或随机生成（见 [`docs/migration-map.md`](../docs/migration-map.md)）。

## install-two-node.sh

> **已废弃**，请使用 [`ograc-skills/ograc-two-node-deploy`](../ograc-skills/ograc-two-node-deploy/SKILL.md)。

旧的单文件两节点部署脚本（858 行，交互式问答，口令通过命令行参数传入）。保留仅为兼容既有操作习惯，不再接受功能修改；计划删除或移入 `tools/legacy/`。
