# ograc-sim-single

单文件创建 oGRAC 单集群 LUN 开发环境（4 个 LUN，每个 LUN 两条 loopback 路径）。脚本内嵌 Dockerfile 与 CMS `cluster.sh`，不依赖 `docker/lun-sim/` 下的其他文件，复制到 oGRAC 源码树任意目录即可运行。

## 前置条件

- 宿主机安装 Docker，并支持 LIO/configfs、`tcm_loop`、`sg3_utils`。
- oGRAC 源码树包含 `build/build_ograc.sh`；编译还需要三方库，默认搜索源码根目录及 `third_party/`，也可设置 `THIRD_PARTY_PATH`。
- `install` 需要 `package/oGRAC-*.tgz` 部署包；已有合适部署包时可跳过 `make`。

## 用法

```bash
cp tools/ograc-sim-single/ograc-sim-single.sh /path/to/oGRAC/
cd /path/to/oGRAC

sudo bash ./ograc-sim-single.sh create         # 创建 LUN、镜像和容器
sudo bash ./ograc-sim-single.sh init           # 安装容器内编译依赖
sudo bash ./ograc-sim-single.sh make debug     # 编译（已有部署包时可跳过）
sudo bash ./ograc-sim-single.sh install debug  # 安装双节点
sudo bash ./ograc-sim-single.sh start
sudo bash ./ograc-sim-single.sh verify
```

常用命令：

```bash
sudo bash ./ograc-sim-single.sh status
sudo bash ./ograc-sim-single.sh sql 0 "SELECT OPEN_STATUS FROM DV_DATABASE;"
sudo bash ./ograc-sim-single.sh login 0
sudo bash ./ograc-sim-single.sh stop
sudo bash ./ograc-sim-single.sh restart
sudo bash ./ograc-sim-single.sh log 100
sudo bash ./ograc-sim-single.sh destroy
```

默认环境目录为 `/home/<用户>/ogracsim_single/cluster`，容器名为 `ograc-dev-<用户>`，默认端口为 CMS `18520/18521`、DSS `19100/19101`、oGRAC `19300/19301`。

## 数据库口令

安装时创建的 sys 口令来自环境变量；未设置则脚本每次随机生成 16 位十六进制串，写入部署用户家目录的 `.sys_pw`（权限 600）：

```bash
sudo OGRAC_SYS_PASSWORD='<你要用的口令>' bash ./ograc-sim-single.sh install debug
```

需要复用既有环境时读取该文件即可：`SYS_PW_FILE=/home/<用户>/.sys_pw`。

## 相关

- 两节点真实集群部署用 [`skills/ograc-deploy-two-node`](../../skills/ograc-deploy-two-node/SKILL.md)；旧的单文件脚本 `install-two-node.sh` 已删除，内容保留在 git 历史中。
