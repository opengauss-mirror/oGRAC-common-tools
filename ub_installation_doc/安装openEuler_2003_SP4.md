# 安装 openEuler 20.03 SP4

本文以 `20.20.20.66` 为例，说明通过 iBMC 挂载 ISO 安装 openEuler 的完整流程。

---

## 一、通过 iBMC 挂载镜像并进入 BIOS

### 1. 登录 iBMC

![](images/openEuler_2003_SP4/01.png)

### 2. 启动独占 HTML5 控制台

![](images/openEuler_2003_SP4/02.png)

### 3. 挂载待安装 OS 版本的 ISO 镜像

![](images/openEuler_2003_SP4/03.png)

### 4. 修改系统启动项，选中光驱

![](images/openEuler_2003_SP4/04.png)

### 5. 重启服务器

### 6. 进入 BIOS

重启后出现下图界面时，按 `F4` 进入 BIOS（部分机型 `F2` 也可）。

![](images/openEuler_2003_SP4/05.png)

随后弹出密码输入框，输入正确密码后按 `Enter` 即可进入 BIOS。

![](images/openEuler_2003_SP4/06.png)

> 若出现如下两个告警界面，继续按 `Enter` 即可，无需关注告警内容。

![](images/openEuler_2003_SP4/07.png)

![](images/openEuler_2003_SP4/08.png)

### 7. 关闭 Support SPCR

进入 BIOS 后，依次设置：

`Advanced` → `MISC Config` → `Support SPCR` = `Disabled`

![](images/openEuler_2003_SP4/09.png)

![](images/openEuler_2003_SP4/10.png)

### 8. 保存并退出

按 `F10` → `Enter` 保存并退出。

![](images/openEuler_2003_SP4/11.png)

---

## 二、安装 openEuler

### 9. 选择从光驱启动并进入安装程序

重启后进入 OS 安装选择界面。

未选择光驱为系统启动项：

![](images/openEuler_2003_SP4/12.png)

已选择光驱为系统启动项：

![](images/openEuler_2003_SP4/13.png)

### 10. 选择安装语言

进入 openEuler 安装配置界面，选择语言为 **English**（有特殊需要可自行修改），然后点击 `Continue`。

![](images/openEuler_2003_SP4/14.png)

### 11. 选择安装目标磁盘

进入完整配置界面后，主要配置 `SYSTEM` 中的 `INSTALLATION DESTINATION`，指定系统安装到哪个磁盘。

![](images/openEuler_2003_SP4/15.png)

选择一个安装盘，勾选 `Automatic`，自动进行分区。

![](images/openEuler_2003_SP4/16.png)

![](images/openEuler_2003_SP4/17.png)

界面会显示当前分区。点击右下角 `Delete all`，再 `Reclaim space` 即可。

![](images/openEuler_2003_SP4/18.png)

### 12. 设置 Root 密码

配置 `USER SETTINGS` 中的 `ROOT PASSWORD`。

![](images/openEuler_2003_SP4/19.png)

### 13. 开始安装

设置完成后，点击左上角 `Done` 返回下图界面。确认已无红色告警文字后，点击右下角 `Begin Installation`。

![](images/openEuler_2003_SP4/20.png)

### 14. 等待自动安装完成

进入自动安装界面：

![](images/openEuler_2003_SP4/21.png)

安装完成后，界面会停留在下图状态，点击右下角 `Reboot System` 即可。

![](images/openEuler_2003_SP4/22.png)

![](images/openEuler_2003_SP4/23.png)

---

## 三、安装后网络配置

### 15. 修改网卡 IP 配置

按第一张图所示修改网络配置文件：

![](images/openEuler_2003_SP4/24.png)

![](images/openEuler_2003_SP4/25.png)

重新加载并启用网卡连接：

```shell
nmcli connection reload
nmcli connection up enp33s0f0np0
```

### 16. 修改子网掩码（可选）

如需将 `/24` 改为 `/23`：

```shell
sudo nmcli connection modify enp33s0f0np0 ipv4.addresses 20.20.21.117/23
sudo nmcli connection up enp33s0f0np0
```

### 17. SSH 连接报错处理

若 SSH 因旧主机密钥报错失败，删除 `known_hosts` 中对应 IP 的旧记录，下次连接时重新确认信任：

```shell
ssh-keygen -R <IP>
```

![](images/openEuler_2003_SP4/26.png)
