# AX6600 自编译固件（axrbl 定制）

> 本仓库 fork 自 [ones20250/Openwrt-AX6600](https://github.com/ones20250/Openwrt-AX6600)，
> 用于给自用的**京东云 AX6600「雅典娜」**出一版定制固件。
>
> **本 README 已按我们的实际情况重写**，与上游原文差异很大：
> 上游的 WiFi 信道建议、插件清单、默认地址都跟我们的实际不符，照抄会踩坑。
> 上游原文可用 `git show origin/main:README.md` 查看。

---

## 1. 我们对上游做了什么（变更记录）

按时间倒序。这些改动**全部只存在于我们 fork 的 `main` 分支**，不会推给上游作者；
若某条对上游有价值，就从 fork 开新分支单独挑出来发 PR。

| # | 改动 | 落点 | 说明 |
|---|---|---|---|
| 5 | 重写本 README | `README.md` | 修正 WiFi 信道建议、插件清单、默认地址；记录远端结构与踩坑 |
| 4 | 移除 Docker 全家桶（9 项） | `Config/GENERAL_AX6600_PLUS.txt` | 所有服务都用原生二进制；**保留 `kmod-ikconfig`**（`/proc/config.gz`） |
| 3 | 关 PassWall2（11 项）+ geo 数据；关打印服务；加 aria2 / btrfs | 同上 | 只用 OpenClash |
| 2 | `PROFILE: PURE → PLUS`；加 `push` 触发；追加定制包组 | `.github/workflows/QCA-ALL.yml`、`GENERAL_AX6600_PLUS.txt` | 让 push 改 `Config/**` 即自动编译 |
| 1 | `kmod-usb-net-{rndis,cdc-ncm,cdc-ether,huawei-cdc-ncm}` → `=y` | `Config/GENERAL_AX6600.txt` | 手机 USB 共享上网 |

**定制一律追加在 `Config/GENERAL_AX6600_PLUS.txt` 末尾** —— 因为 `.config` 是顺序拼接、后写覆盖先写（见 §6）。

## 2. 硬件

| 项 | 值 |
|---|---|
| 设备 | 京东云 AX6600「雅典娜」 |
| board / 平台 | `jdcloud,re-cs-02`，`qualcommax/ipq60xx` |
| SoC / 内存 | Qualcomm IPQ6010 / 1 GB |
| eMMC | `mmcblk0` ≈ 230 GiB（256 GB 级） |
| U-Boot | 社区「不死 U-Boot」`2024.05.10_12:22:07` — **不要重刷** |
| 分区表 | 双分区 `2048M` rootfs（no-last-partition）；`mmcblk0p18` = rootfs；overlay 走 `/dev/loop0` 2 GB |
| ⚠️ storage 分区 | **尚未创建**（no-last-partition 丢掉了最后那个大分区），需用 `sgdisk` 新建 |

## 3. 我们用到的固件能力

设备用途决定了包里该有什么：

1. **公寓路由器** — LAN 与家里保持一致 `172.16.0.1/24`
2. **WAN 用手机 USB 共享上网** — 依赖 USB RNDIS/NCM 系列内核模块
3. **备份服务器 + 私有 git mirror** — 用上 eMMC 那 ~226 GB 空间

## 4. 相对上游的改动（我们做的）

### 3.1 新增

| 类别 | 包 |
|---|---|
| mesh VPN | `netbird`（与公司那套一致；无 LuCI，CLI 配） |
| eMMC 体检 | `mmc-utils`（寿命 / EOL） |
| 磁盘管理与健康 | `luci-app-diskman`、`smartmontools`、`hdparm`、`luci-app-hd-idle` |
| 备份 / mirror | `rsync`、`restic`、`zstd`、`git` |
| 文件共享与浏览 | `luci-app-cifs-mount`、`luci-app-filemanager` |
| 运维 | `luci-app-vnstat2`（流量统计）、`luci-app-commands`（LuCI 跑脚本） |
| 下载 | `aria2`、`luci-app-aria2` |
| 数据分区快照 | `kmod-fs-btrfs`、`btrfs-progs` |
| USB 手机共享 | `kmod-usb-net-{rndis,cdc-ncm,cdc-ether,huawei-cdc-ncm}` → `=y` |
| 排查用 | `kmod-ikconfig`（保留 `/proc/config.gz`） |

### 3.2 删除

| 类别 | 包 | 原因 |
|---|---|---|
| Docker 全家桶 | `docker`、`dockerd`、`docker-compose`、`luci-app-dockerman`、`luci-lib-docker`、`cgroupfs-mount`、`tini`、`kmod-nf-ipvs`、`kmod-veth` | 所有服务都用原生二进制跑，Docker 是纯负担 |
| PassWall2 生态 | 11 项 | 只用 OpenClash |
| 打印服务 | `kmod-usb-printer`、`p910nd`、`luci-app-p910nd` | 不需要 |
| geo 数据 | `v2ray-geoip`、`v2ray-geosite`、`v2ray-geoview` | 已核实 OpenClash 不依赖 |

> ⚠️ **上游 Release 说明里那句 "预装 OpenClash、PassWall2、Docker/Dockerman…" 是过期文案**，
> 由 `WRT-CORE.yml` 的 `WRT_PROFILE_DESC` 生成，还没同步我们的删减。以本文件为准。

## 5. ⚠️ WiFi 信道：不要照上游设

**这是本设备最容易踩的坑。** ath11k 在本机上的监管域很反直觉，实测（以 `iw phy <phy> channels` 为准）：

| 射频 | 归属 | 实测可用 | ⚠️ 禁用 |
|---|---|---|---|
| `phy0` | AHB / radio0（5G-1，4×4） | `149–169`、`100–144`(DFS) | **36–48 全禁用** |
| `phy2` | PCIe / radio2（5G-2，2×2） | `36–48`（+52–64 DFS） | **100 以上全禁用** |
| radio1 | 2.4G | `11` / `HE20` | — |

**正确配置：**

| WiFi | 信道 | 带宽 |
|---|---|---|
| 2.4G | `11` | 20 MHz |
| 5G-1（radio0，4×4） | **`149`** | 80 MHz |
| 5G-2（radio2，2×2） | **`36`** | 80 MHz |

通用：地区 `CN`、加密 `WPA2-PSK`（CCMP）。

> 上游 README 建议 5G-1 用信道 `44`、5G-2 用 `149`。**在这台设备上会导致 AP 起不来**
> （hostapd 报 `not allowed for AP mode`）。上游那张表是通用建议，不适用于本机的 ath11k 监管域。

### 为什么不把信道设成 `auto`（结论：就用固定 149 / 36）

`auto` 就是 OpenWrt 的 **ACS**（Automatic Channel Selection）。它能"自动避让冲突"这个说法**只对一半**：

| 机制 | 触发时机 | 会不会自动换信道 |
|---|---|---|
| ACS | **仅启动/重启 wifi 时** | 选**一次**，之后一直钉在那个信道上 |
| DFS 雷达检测 | **仅限 DFS 信道**（100–144），且**只对雷达信号** | ✅ 会立刻撤离并换信道（发 CSA，客户端掉线重连） |
| 「运行中信道变拥挤了」 | 邻居新加了个 AP | ❌ **没有任何机制会响应** |

关键限制，别抱期待：

- **ACS 不做运行中持续监测。**它避得开开机时已有的冲突，避不开运行中新增的冲突。
- **"别人和我抢同一个信道"不会触发任何自动调整。**hostapd 没有"持续频谱感知 + 择优切换"这个功能；
  只有**雷达**能让它自己跳信道。
- 想真的运行中自动换信道，只能自己写脚本定时 `iw scan` 再判优切换——但**换信道会让所有客户端掉线重连**，
  对一台 7×24 的路由器 + 备份服务器来说得不偿失。**本仓库不这么做。**

那为什么不开 `auto`？因为**在这台设备的监管域下，`auto` 会把射频选到 DFS 信道上**：

| 射频 | `auto` 可能选到 | 风险 |
|---|---|---|
| `phy0`（radio0，5G-1） | `149–169` 或 **`100–144`(DFS)** | ⚠️ 选到 DFS 要做 **60 秒 CAC**（静默监听雷达），期间 AP 完全不可用；<br>运行中误判雷达则 **AP 直接停播**，5G 短暂断流 |
| `phy2`（radio2，5G-2） | `36–48` 或 **`52–64`(DFS)** | ⚠️ 同上 |

**`149` 与 `36` 都是非 DFS 信道 → 永远不用 CAC、永远不会被雷达踢下线。**
对这台要长期在线的设备，**可用性 > 那点理论抗干扰收益**。另外 `auto` 每次重启结果可能不同，
那些只认 BSSID 的智能家居设备会更难受。

**想换信道时：手动勘测后定死，不要交给 `auto`。**

```bash
# 在路由器上跑，看哪个信道最空（会短暂影响自身 AP）
iw dev wlan0 scan | grep -E "SSID|channel" | sort | uniq -c | sort -rn
```

**如果哪天真想用"自动但零 DFS 风险"**：把 ACS 的信道范围限制在非 DFS 段，
即 `/etc/config/wireless` 里给对应 radio 加 `option channels '149 153 157 161 165'`（radio0）
或 `option channels '36 40 44 48'`（radio2），再设 `option channel 'auto'`。
但如上所述，非 DFS 段本身只有 4–5 个信道，挑不出多少花来，**仍推荐固定 149 / 36**。

> 附：`160MHz` 不建议开。`phy0` 若开 160MHz 需要 `149–177`，而 `phy2` 的 160MHz 会横跨
> `36–64`（含 DFS 52–64）→ 又把雷达风险引回来。用 80MHz 即可。

## 6. 编译机制

- `.config` = **按顺序拼接**：
  `Config/IPQ60XX-WIFI-YES.txt` + `Config/GENERAL_AX6600.txt` + `Config/GENERAL_AX6600_<PROFILE>.txt`
  → **后写覆盖先写**（Kconfig 最后一次赋值生效）。**我们的定制一律追加在 `GENERAL_AX6600_PLUS.txt` 末尾。**
- **profile 只能是 `PURE` 或 `PLUS`**：`WRT-CORE.yml` 里有 `case` 判断，其它值 `exit 1`；
  且 `Scripts/Packages.sh` 与 `WRT-CORE.yml` 两处都用 `if [[ "$WRT_PROFILE" == "PLUS" ]]` 门控
  OpenClash / PassWall2 / partexp / viking 的源码 clone 和 `passwall_packages` feed。
  → **只要用 OpenClash 就必须叫 `PLUS`，别改名。**
- 编译完会 `rm -rf bin/targets/**/packages`，**Release 里只有固件、没有独立 kmod**。
  → **kmod 必须随固件集成**（ABI hash 会变，刷完事后装不了）。
- 产物命名：`<源码owner>-<分支>-<profile小写>-<设备>-<时间>.<ext>`
- **构建缓存**：cache key 含源码 commit，**fork 无法复用上游作者的缓存**。
  实测首次冷编译约 **2 小时 12 分**（其中 `Compile Firmware` 约 2 小时）；有缓存后明显更快。

### 触发编译

| 方式 | 说明 |
|---|---|
| `push` 到 `main` 且改动 `Config/**` | **自动触发**（实测生效） |
| Actions → `QCA-ALL` → Run workflow | 手动全量 |
| Actions → `WRT-TEST`，`TEST=true` | **只生成最终 `.config`，不编译**。<br>用来验证包名是否被 `make defconfig` **静默丢弃** |

> 💡 **`CONFIG_PACKAGE_xxx=y` 只是意图，不是保证。**
> 如果该包在 feeds 里不存在，`make defconfig` 会静默丢掉它——编译照样成功、固件照样出，但里面没这个东西。
> **唯一真相是 Release 里的 `.manifest`**，或者用 `TEST=true` 生成的最终 `Config-*.txt` 反查。

### 默认值（在 `QCA-ALL.yml` 里）

| 变量 | 当前值 | 说明 |
|---|---|---|
| `WRT_NAME` | `OWRT` | 主机名 |
| `WRT_SSID` / `WRT_WORD` | `OWRT` / `12345678` | WiFi |
| `WRT_IP` | `192.168.10.1` | **管理地址**（不是 192.168.1.1；也不是我们想要的 172.16.0.1） |
| `WRT_THEME` | `bootstrap` | 主题 |

> ⚠️ **刷 `factory.bin` 会清除配置**（20240510 版 u-boot 起，刷固件即清配置数据）。
> 想让刷完直接就是 `172.16.0.1` / `Password01!`，**先改 `WRT_IP` / `WRT_WORD` 再重编**。
> 走系统内 `sysupgrade` 则会保留现有配置。

## 7. 仓库与远端（重要）

本仓库同时扮演两个角色，用**两个远端**区分：

| 远端 | 指向 | 角色 |
|---|---|---|
| `origin` | `git@github.com:ones20250/Openwrt-AX6600.git` | **上游原始出处**，只用来跟进更新 |
| `upstream` | `git@github.com:axrbl/Openwrt-AX6600.git` | **我们自己的 fork**，我们推送到这里，CI 也在这里跑 |

> 命名确实容易混：**`origin` = 原始作者**，**`upstream` = 我们自己的**。
> 这是刻意按"要保持同步的那一方叫 origin"来定的。记住：
> **`origin` 是只读的源头，`upstream` 是我们的家。**

分支策略：**只有 `main` 一条分支，定制直接做在 `main` 上。**

### 跟进上游更新

```powershell
$git = "C:\Users\raxia\Tools\PortableGit\cmd\git.exe"
$repo = "C:\Users\raxia\devops\Openwrt-AX6600"

# 1) 取上游最新
& $git -C $repo fetch origin

# 2) 看上游带来了什么
& $git -C $repo log --oneline HEAD..origin/main

# 3) 合并进我们的 main（因为我们在 main 上定制，这里可能产生冲突）
& $git -C $repo merge origin/main

# 4) 推回我们自己的 fork（注意是 upstream，不是 origin）
& $git -C $repo push upstream main
```

> ⚠️ 因为定制和上游更新都在 `main` 上，第 3 步**可能出现冲突**，
> 典型冲突点是 `Config/GENERAL_AX6600_PLUS.txt` 和 `.github/workflows/`。
> 若上游改动碰到了我们定制的那些行，需要手工合。
>
> 想避免冲突的话，正解是"上游纯净镜像 + 定制单独分支"，
> 但当前选择是单分支，接受偶发冲突。

### 推送目标别搞错

`main` 的 tracking 指向 `origin/main`（为了 `fetch`/`log` 方便）。而 Git 的 `push` 默认跟随 tracking 远端，
所以**裸 `git push` 会试图推向上游**——会失败（我们对 `ones20250` 没有写权限，是明确报错，不会静默推错地方）。

⚠️ 注意：**`--set-upstream` 不要用来"修"这个**，那会把 tracking 改成 `upstream/main`，
反而让 `git fetch` / `git log HEAD..origin/main` 这些跟进上游的常用操作变得别扭。

为此 `setup-remotes.ps1` 装了别名，推送还是四个字母：

```powershell
# 看上游有没有新提交，并列出差异
git syncf

# 把上游更新合进我们的 main（可能有冲突）
git merge origin/main

# 推我们自己的 fork（等价于 git push upstream main），触发 CI
git pushf
```

完整写法（不用别名时）：

```powershell
# 拉取同步（无需参数，因为 tracking 指向 origin/main）
& $git -C $repo pull

# 推送必须显式指定 upstream
& $git -C $repo push upstream main
```

## 8. 刷机

📖 完整流程见 [`Docs/刷机救砖教程.md`](Docs/刷机救砖教程.md)（开 SSH / 备份分区 / 刷 U-Boot / 9008 救砖）。

### 关键约束

- **本 u-boot 支持 kernel 为 6 MB 的 OP `factory.bin`**（如大雕 QWRT 那种），
  以及官方原厂固件 `JDCOS-JDC02`。
- 官方 ImmortalWrt 的 `sysupgrade.bin`(tar) 和 `initramfs-uImage.itb` **不能用**。
- **我们的 `squashfs-factory-*.bin` 就是 u-boot 能吃的格式**，可以直接刷。
  （它约 80 MB，别和"kernel 6 MB"混淆：6 MB 指 kernel 分区，整包尺寸可以更大。）
- u-boot webui 入口：`/` = 固件（字段名 `firmware`）；`/img.html` = GPT/IMG（字段名 **`img`**）；
  `/art.html`、`/cdt.html`、`/uboot.html`。**写入成功 = 绿灯亮 3 秒。**
- 进 failsafe：**按住 reset 上电** → 红灯闪 5 次 → 变蓝 → webui 在 `192.168.1.1`。
- 若进不去 u-boot webui：把网卡速率手动改成 **10M 全双工**再试（网卡与 u-boot 驱动兼容性问题），刷好改回自动协商。

### 两个文件怎么选

| 文件 | 用途 |
|---|---|
| `*-factory-*.bin` | 经 **u-boot webui** 刷（会清配置） |
| `*-sysupgrade-*.bin` | 已在 OpenWrt/ImmortalWrt 上，**系统内升级**（保留配置） |

### 刷机前

```powershell
# 校验下载完整性（Windows）
certutil -hashfile <固件文件名>.bin SHA256
# 与 Release 里的 sha256sums.txt 对应行比对
```

## 9. 刷完的待办

1. **建 storage 分区**：
   ```bash
   sgdisk -e -n 0:0:0 -c 0:storage -t 0:1B1720DA-A8BB-4B6F-92D2-0A93AB9609CA -p /dev/mmcblk0
   ```
   然后 `mkfs.btrfs`（建议建 `@data` 子卷，方便快照）
2. **配 netbird**（无 LuCI）：`netbird up --setup-key <setup key>`；
   init 脚本 `/etc/init.d/netbird`，配置在 `/root/.config/netbird/`
3. **配 USB RNDIS WAN**：手机开「USB 共享网络」→ 出现 `usb0` →
   把 `network.wan` 的 device 指过去 + 配 firewall zone
4. **Samba / 备份 / git mirror**：Forgejo 直接放 **arm64 单文件**即可
   （无 OpenWrt 包、不需要 Docker、不需要重编固件）

## 10. 已知坑

### 设备侧

- **绝对不要用 `apk add --force-broken-world`** — 会删掉 220 个包（内核 + kmod）把系统搞挂。
- `/overlay`、`/opt/docker` 之类占位符**不能直接 `rm`**（会连数据一起删），要用 `mknod <path> c 0 0` 重建。
- `no-last-partition` 分区表刷完后，**最后那个大分区要自己建**。
- 这版固件**默认管理地址是 `192.168.10.1`**（不是 `192.168.1.1`）。

### 编译侧

- **kmod 必须随固件集成**，Release 不含独立 kmod 包。
- `make defconfig` 会静默丢弃 feeds 里不存在的包 → **必须用 `.manifest` 或 `TEST=true` 验证**。
- `WRT_PROFILE` 不能改名，只能 `PURE` / `PLUS`。

### 网络 / 传输

- **公司网络会 reset GitHub 的 https git 传输**（`Recv failure: Connection was reset`）→ **用 SSH**：
  `git@github.com` 或 `ssh.github.com:443`。本仓库远端已全部用 SSH。
- 未认证 GitHub API 限流 **60 次/小时**。

## 11. 文档

| 文件 | 内容 |
|---|---|
| [`Docs/刷机救砖教程.md`](Docs/刷机救砖教程.md) | 开 SSH / 备份分区 / 刷 U-Boot / 9008 救砖 |
| `HANDOFF.md` | 上一轮排查的详细交接（**本地未跟踪文件，不要 commit**） |
| `Config/GENERAL_AX6600_PLUS.txt` | 我们全部定制的落点 |

## 12. 上游

| 仓库 | 关系 |
|---|---|
| [ones20250/Openwrt-AX6600](https://github.com/ones20250/Openwrt-AX6600) | 本仓库的 **fork 来源**，即 `origin` |
| [ones20250/immortalwrt_ipq](https://github.com/ones20250/immortalwrt_ipq) | **CI 编译时拉取的固件源码**（`QCA-ALL.yml` 的 `SOURCE` 矩阵），与 fork 关系无关 |

## 13. 免责声明

刷机有风险。本固件仅供自用与学习研究。请确认设备型号匹配，并提前备份数据。
