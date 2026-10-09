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
| 7 | 重写本 README | `README.md` | 记录实测结论、构建机制、踩坑 |
| 6b | **双 WAN 自动故障切换（新增）** | `Config/GENERAL_AX6600_PLUS.txt`、`files/etc/config/mwan3`、`files/etc/uci-defaults/99-ax6600-dualwan`、`WRT-CORE.yml` | mwan3 健康探测 + 手机 USB 共享为主、物理网口为备（见 §9） |
| 6 | **无线默认值机制（新增）** | `Scripts/Settings.sh`、`files/etc/uci-defaults/99-ax6600-wifi`、`WRT-CORE.yml`、`QCA-ALL.yml` | 上游**完全没有**信道/功率的构建期机制。补上：mac80211.uc 注入 txpower；uci-defaults 设定 `auto` 信道 + 非 DFS 白名单 |
| 5 | LAN 默认地址 + 两个新变量 | `QCA-ALL.yml` | `WRT_IP` → `172.16.10.1`；新增 `WRT_COUNTRY`、`WRT_TXPOWER` |
| 4 | 修正 Release 说明文案 | `WRT-CORE.yml` | 原文还在宣传已删除的 PassWall2 / Docker |
| 3 | 移除 Docker 全家桶（9 项） | `Config/GENERAL_AX6600_PLUS.txt` | 所有服务都用原生二进制；**保留 `kmod-ikconfig`** |
| 2 | 关 PassWall2（11 项）+ geo 数据；关打印服务；加 aria2 / btrfs | 同上 | 只用 OpenClash |
| 1 | `PROFILE: PURE → PLUS`；加 `push` 触发；追加定制包组<br>`kmod-usb-net-{rndis,cdc-ncm,cdc-ether,huawei-cdc-ncm}` → `=y` | `.github/workflows/QCA-ALL.yml`、`Config/*` | 手机 USB 共享上网 |

**定制一律追加在 `Config/GENERAL_AX6600_PLUS.txt` 末尾** —— 因为 `.config` 是顺序拼接、后写覆盖先写（见 §6）。

## 2. 硬件

| 项 | 值 |
|---|---|
| 设备 | 京东云 AX6600「雅典娜」 |
| board / 平台 | `jdcloud,re-cs-02`，`qualcommax/ipq60xx` |
| SoC / 内存 | Qualcomm IPQ6010 / 1 GB（实测可用 587 MB） |
| eMMC | `mmcblk0` = 483,328,000 扇区 ≈ 230.5 GiB |
| U-Boot | 社区「不死 U-Boot」`2024.05.10_12:22:07` — **不要重刷** |
| 分区表 | 双分区 `2048M` rootfs；`mmcblk0p18` = rootfs；overlay 走 `/dev/loop0` 2 GB（f2fs） |
| 数据分区 | **`mmcblk0p27` / `storage` = 226.8 GiB，已格式化为 btrfs 并开机自挂载到 `/mnt/storage`**（见 §10） |

## 3. 我们用到的固件能力

设备用途决定了包里该有什么：

1. **公寓路由器** — LAN `172.16.10.1/24`
2. **WAN 用手机 USB 共享上网** — 依赖 USB RNDIS/NCM 系列内核模块
3. **备份服务器 + 私有 git mirror** — 用上 226.8 GiB 的 storage 分区

## 4. 相对上游的改动（包层面）

### 4.1 新增

| 类别 | 包 |
|---|---|
| mesh VPN | `netbird`（与公司那套一致；无 LuCI，CLI 配） |
| eMMC 体检 | `mmc-utils`（**命令是 `mmc`，在 `/sbin/mmc`**，不是 `mmc-utils`） |
| 磁盘管理与健康 | `luci-app-diskman`、`smartmontools`、`hdparm`、`luci-app-hd-idle` |
| 备份 / mirror | `rsync`、`restic`、`zstd`、`git` |
| 文件共享与浏览 | `luci-app-cifs-mount`、`luci-app-filemanager` |
| 运维 | `luci-app-vnstat2`、`luci-app-commands` |
| 下载 | `aria2`、`luci-app-aria2` |
| 数据分区快照 | `kmod-fs-btrfs`、`btrfs-progs` |
| USB 手机共享 | `kmod-usb-net-{rndis,cdc-ncm,cdc-ether,huawei-cdc-ncm}` → `=y` |
| 排查用 | `kmod-ikconfig`（保留 `/proc/config.gz`） |

### 4.2 删除

| 类别 | 包 | 原因 |
|---|---|---|
| Docker 全家桶 | `docker`、`dockerd`、`docker-compose`、`luci-app-dockerman`、`luci-lib-docker`、`cgroupfs-mount`、`tini`、`kmod-nf-ipvs`、`kmod-veth` | 所有服务都用原生二进制跑 |
| PassWall2 生态 | 11 项 | 只用 OpenClash |
| 打印服务 | `kmod-usb-printer`、`p910nd`、`luci-app-p910nd` | 不需要 |
| geo 数据 | `v2ray-geoip`、`v2ray-geosite`、`v2ray-geoview` | 已核实 OpenClash 不依赖 |

> 本机固件实测：**26/26 定制包全部到位，14 项应删的确实都不在**（用 `.manifest` 与 `apk info` 双重确认）。

## 5. ⚠️ WiFi 配置（本设备最容易踩的坑）

### 5.1 实测监管域（`iw phy <phy> channels`）

`country=CN` 下，本机两个 5G 射频的可用信道**完全互补且互不重叠**：

| 射频 | 归属 | 可用非 DFS | 可用 DFS | 最大功率 | 带宽能力 |
|---|---|---|---|---|---|
| `phy0` | AHB / radio0（5G-1，**4×4**） | **149 / 153 / 157 / 161 / 165** | **无**（36–144 全部 disabled） | 36 dBm | VHT80 |
| `phy1` | AHB / radio1（2.4G） | 1–13 | — | 27 dBm | HT40 |
| `phy2` | PCIe / radio2（5G-2，2×2） | **36 / 40 / 44 / 48** | 52–64（Radar detection，CAC 60000ms，24 dBm） | 30 dBm | VHT160 |

### 5.2 我们的配置（也是固件默认值）

三个射频**全部使用 ACS（`auto`）+ 信道白名单**，功率统一 **14 dBm**：

| WiFi | 射频 | 信道 | 白名单（`channels`） | 带宽 | 功率 |
|---|---|---|---|---|---|
| 2.4G | radio1 | `auto` | `1 2 3 4 5 6 7 8 9 10 11 12 13` | HE20 | 14 dBm |
| 5G-1（4×4） | radio0 | `auto` | `149 153 157 161` | HE80 | 14 dBm |
| 5G-2（2×2） | radio2 | `auto` | `36 40 44 48` | HE80 | 14 dBm |

SSID 三个射频统一 `OWRT`，加密 `psk2+ccmp`。国家码 `CN`。

**白名单不是可选项，是必需的。** 实测（见 §5.7）：不加白名单时 ACS 会选到
**信道 14**（2.4G）和 **DFS 信道**（5G 低段），两者都会让 AP 直接起不来。

### 5.3 为什么功率只给 14 dBm

用途是 **20 平单间、一个房间内覆盖**，不是穿墙覆盖整栋楼。

- 14 dBm ≈ 25 mW，对一间房有充足余量
- 上游从未设置 `txpower`，**驱动默认值是 24–27 dBm（250–500 mW）**，对一间房严重过量
- 功率过大的实际坏处：抬高自身底噪、增加邻频干扰、客户端"看到强信号但速率跑不动"
- 需要更大覆盖时再调高即可（`uci set wireless.radioX.txpower=<值>`）

### 5.4 为什么用 `auto` + 白名单（而不是固定信道，也不是裸 `auto`）

先说 ACS（`auto`）的能力边界，别抱错误期待：

| 机制 | 触发时机 | 会不会自动换信道 |
|---|---|---|
| ACS（`auto`） | **仅启动/重启 wifi** | 选**一次**，之后钉住不动 |
| DFS 雷达检测 | 仅 DFS 信道，仅雷达信号 | ✅ 会撤离换信道（发 CSA，客户端掉线） |
| 「运行中信道变拥挤」 | 邻居新加 AP | ❌ **没有任何机制响应** |

**ACS 不做运行中持续监测，"别人抢信道"不会触发任何自动调整。** 它只在启动时挑一次最好的。

在这个前提下，「`auto` + 白名单」是最优组合：

- **`auto` 的价值**：本机 2.4G 实测有 **13 个邻居 AP** 挤在信道 1/3/6/7/9/10/11，
  而 ACS 一次就选中了没人用的信道（实测选到 13、11）。固定信道做不到这点。
- **白名单的必要性**：不加限制时 ACS 会选到**会导致 AP 宕机的信道**（见 §5.7）。
- **白名单同时封死了 DFS**：radio2 的 52–64 在 CN 下依然带 `Radar detection`，
  白名单把它排除后，`auto` 物理上不可能落到 DFS，**永远不会触发 60 秒 CAC、也不会被雷达踢下线**。

> 对比「固定信道」：固定值失去了自适应性，而且邻居情况一变就得手动改。
> 对比「裸 `auto`」：会宕机或落进 DFS。**只有 `auto` + 白名单两者同时成立才对。**

### 5.5 为什么国家码保持 `CN`（不改 `US`）

`US` 唯一的实际变化是把 **DFS 信道**解禁（`phy2` 的 52–64、`phy0` 的更多频段）：

- 现有非 DFS 信道配合白名单已足够：radio0 有 4 个候选、radio2 有 4 个、2.4G 有 13 个
- `US` 还会**禁用 2.4G 的 12–13 信道**（FCC 只到 11），2.4G 本就拥挤，少两个选择更糟
- 设备按 `CN` 出厂认证，改 `US` 理论上有法规问题
- 日志里本来就有 `ath11k_pci: failed to perform regd update : -22`，动国家码会引入新不确定行为

**改国家码并不能让 `auto` 变安全——白名单才能。** 而白名单已经做到了，所以没必要改。

### 5.6 上游 README 的信道建议是错的

上游建议 5G-1 用 `44`、5G-2 用 `149`。**在本机 `phy0` 的 36–48 全部禁用**，
照它设会让 AP 直接启动失败：

```
hostapd: phy0-ap0: IEEE 802.11 Configured channel (100) or frequency (5500) not found
hostapd: phy0-ap0: Hardware does not support configured channel
hostapd: Frequency 5500 (primary) not allowed for AP mode, flags: 0x109 RADAR
hostapd: phy0-ap0: interface state COUNTRY_UPDATE->DISABLED
hostapd: phy0-ap0: Unable to setup interface.
```

**这个错误上游也犯在了源码里**：DTS 给 `phy0` 的 `default_channel` 是 **100**（见 §6.3），
所以**刷新固件后 5G-1 默认就是不工作的**。我们已在首次启动时用白名单修正。

### 5.7 ⚠️ 实测：裸 `auto` 会选到让 AP 宕机的信道

这是本次排查最重要的发现，也是白名单存在的直接原因。

**（1）2.4G 不加白名单 → ACS 选中信道 14 → AP 彻底宕机**

```
hostapd: Disable OFDM/HT/VHT/HE/EHT on channel 14     ← 14 只能跑老式 802.11b
hostapd: phy1-ap0: ACS-COMPLETED freq=2484 channel=14
hostapd: phy1-ap0: IEEE 802.11 Failed to prepare rates table.
hostapd: phy1-ap0: interface state ACS->DISABLED
hostapd: phy1-ap0: AP-DISABLED
```

为什么 ACS 会选 14？因为 CN 监管域下信道 14 是「可用」的，而它与 1–13 **完全频段隔离**，
按"最不拥挤"打分自然排第一。但信道 14 只能在 802.11b 下工作，现代 hostapd 直接放弃。
**加上 `channels='1 2 3 ... 13'` 后立刻正常**（实测选到 11，`phy1-ap0 UP`）。

> 注意：`iw phy phy1 channels` 里信道 14 **没有 `disabled` 也没有 `no-IR` 标记**，
> 所以**光看监管域输出无法发现这个坑**，必须靠白名单排除。

**（2）5G 低段不加白名单 → 可能落到 DFS 52–64**

```
* 5260 MHz [52]
  Radar detection
  DFS CAC time: 60000 ms        ← 开机要静默 60 秒，且会被雷达踢下线
```

ACS 日志显示它**确实会扫描**这些 DFS 信道（`ACS: Survey for freq 5260/5280/5300/5320 ...`），
白名单把它排除后，实测选中 44（非 DFS），全程无 CAC 无雷达事件。

**（3）白名单生效的正面证据**

```
phy0-ap0  Channel: 157  HE80  14 dBm  UP    ← 在白名单 149/153/157/161 内
phy1-ap0  Channel: 11   HE20  14 dBm  UP    ← 在白名单 1-13 内（没选 14）
phy2-ap0  Channel: 44   HE80  14 dBm  UP    ← 在白名单 36/40/44/48 内（没选 DFS）
hostapd: phy2-ap0: ACS-COMPLETED freq=5220 channel=44
```

## 6. 编译机制

### 6.1 配置拼接

- `.config` = **按顺序拼接**：
  `Config/IPQ60XX-WIFI-YES.txt` + `Config/GENERAL_AX6600.txt` + `Config/GENERAL_AX6600_<PROFILE>.txt`
  → **后写覆盖先写**（Kconfig 最后一次赋值生效）。**我们的定制一律追加在 `GENERAL_AX6600_PLUS.txt` 末尾。**
- **profile 只能是 `PURE` 或 `PLUS`**：`WRT-CORE.yml` 里有 `case` 判断，其它值 `exit 1`；
  且两处都用 `if [[ "$WRT_PROFILE" == "PLUS" ]]` 门控 OpenClash / partexp / viking 的 clone 和 `passwall_packages` feed。
  → **只要用 OpenClash 就必须叫 `PLUS`，别改名。**
- 编译完会 `rm -rf bin/targets/**/packages`，**Release 里只有固件、没有独立 kmod**。
  → **kmod 必须随固件集成**（ABI hash 会变，刷完事后装不了）。
- **构建缓存**：cache key 含源码 commit。实测首次冷编译约 **2 小时 12 分**；命中缓存会明显更快。

### 6.2 默认值的三个注入点（重要）

`Scripts/Settings.sh` 在 `./wrt/` 下、**编译前**运行，是设置默认值的唯一入口：

| 文件 | 改什么 | 变量 |
|---|---|---|
| `package/base-files/files/bin/config_generate` | LAN 默认 IP、主机名 | `WRT_IP`、`WRT_NAME` |
| `package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc` | SSID、密码、**发射功率** | `WRT_SSID`、`WRT_WORD`、`WRT_TXPOWER` |
| `<设备>.dts`（生成 `/etc/board.json`） | **各射频 default_channel** | 见下 |

`mac80211.uc` 是**首次开机生成 `/etc/config/wireless` 的 ucode 生成器**，关键三行：

```
set ${s}.channel='${channel}'      ← channel 来自 board.json 的 default_channel
set ${s}.txpower='14'              ← 这一行是【我们插入的】，上游没有
set ${si}.ssid='OWRT' / key='...'  ← 硬编码字面量，Settings.sh 用 sed 改
```

### 6.3 ⚠️ 信道默认值来自 DTS，不在 uc 里

`/etc/board.json` 里各射频的 `default_channel` 是**构建时从设备树 DTS 生成**的，实测：

```
phy0: default_channel = 100   ← 错的！phy0 禁用 36-144，只能是 149-165
phy1: default_channel = 1
phy2: default_channel = 36
```

所以**改 `mac80211.uc` 改不动信道**。上游 DTS 路径与命名不稳定（我们没能在上游仓库里
定位到该设备的 DTS），因此**不靠 DTS 补丁**，改用下面的兜底机制。

### 6.4 兜底机制：`files/etc/uci-defaults/99-ax6600-wifi`

`WRT-CORE.yml` 会把仓库的 `files/` 拷进固件源码树（OpenWrt 会把源码根的 `files/`
叠加到 rootfs，于是 `files/etc/uci-defaults/xx` → 镜像里的 `/etc/uci-defaults/xx`，
**首次开机执行一次**）。

这个脚本**按频段而不是按 radio 名字**纠正，所以不依赖 DTS、不依赖 radio 编号：

| 频段判据 | 目标信道 |
|---|---|
| `band=2g` | `1` |
| `band=5g` 且 path 含 `pcie`（低段射频） | `36` |
| `band=5g` 其它（仅 149–165 可用） | `149` |

同时强制 `txpower` 与 `country`。构建时把脚本里的 `__TXPOWER__` / `__COUNTRY__`
占位符替换成实际值。

**已在真机验证**（BusyBox ash）：

```
场景1 出厂错误值 (radio0=100, 无 txpower)
      → "radio0: channel 100 -> 149" / "txpower -> 14"   ✅ 纠正成功
场景2 再跑一遍（幂等性）
      → "所有值已正确，无需改动"                          ✅ 无副作用
场景3 恢复现场
      → radio0=149 / 14dBm 正常，`sh -n` 语法通过
```

### 6.5 触发编译

| 方式 | 说明 |
|---|---|
| `push` 到 `main` 且改动 `Config/**` | **自动触发** |
| Actions → `QCA-ALL` → Run workflow | 手动全量 |
| Actions → `WRT-TEST`，`TEST=true` | **只生成最终 `.config`，不编译**，用来验证包名是否被 `make defconfig` 静默丢弃 |

> 💡 **`CONFIG_PACKAGE_xxx=y` 只是意图，不是保证。**
> 如果该包在 feeds 里不存在，`make defconfig` 会静默丢掉它——编译照样成功、固件照样出，但里面没这个东西。
> **唯一真相是 Release 里的 `.manifest`。**

### 6.6 当前默认值（`QCA-ALL.yml`）

| 变量 | 值 |
|---|---|
| `WRT_NAME` | `OWRT` |
| `WRT_SSID` / `WRT_WORD` | `OWRT` / `12345678`（**刷完自己改**） |
| `WRT_IP` | **`172.16.10.1`** |
| `WRT_COUNTRY` / `WRT_TXPOWER` | `CN` / `14` |
| `WRT_THEME` | `bootstrap` |

> ⚠️ **刷 `factory.bin` 会清除配置**（20240510 版 u-boot 起，刷固件即清配置数据），
> 所以刷完是上面的默认值。走系统内 `sysupgrade` 则保留现有配置。

## 7. 仓库与远端（命名反直觉，务必记住）

| 远端 | 指向 | 角色 |
|---|---|---|
| `origin` | `git@github.com:ones20250/Openwrt-AX6600.git` | **上游原始出处**，只用来跟进更新 |
| `upstream` | `git@github.com:axrbl/Openwrt-AX6600.git` | **我们自己的 fork**，我们推送到这里，CI 也在这里跑 |

> **`origin` 是只读的源头，`upstream` 是我们的家。**

分支策略：**只有 `main` 一条分支，定制直接做在 `main` 上。**

### 跟进上游更新

```powershell
$git  = "C:\Users\raxia\Tools\PortableGit\cmd\git.exe"
$repo = "C:\Users\raxia\devops\Openwrt-AX6600"

& $git -C $repo syncf                 # = fetch origin 并列出上游新提交
& $git -C $repo merge origin/main     # 合进我们的 main（可能冲突）
& $git -C $repo pushf                 # = push upstream main，触发 CI
```

> ⚠️ 因为定制和上游更新都在 `main` 上，第 2 步**可能出现冲突**，典型冲突点是
> `Config/GENERAL_AX6600_PLUS.txt`、`Scripts/Settings.sh` 和 `.github/workflows/`。

### 推送目标别搞错

`main` 的 tracking 指向 `origin/main`（为了 `fetch`/`log` 方便），而 Git 的 `push` 默认跟随 tracking 远端，
所以**裸 `git push` 会试图推向上游**——会失败（对 `ones20250` 没有写权限，是明确报错，不会静默推错地方）。

```powershell
git syncf     # 看上游有没有新东西
git pushf     # 推我们自己的 fork
```

## 8. 刷机

📖 完整流程见 [`Docs/刷机救砖教程.md`](Docs/刷机救砖教程.md)。

### 关键约束

- **本 u-boot 支持 kernel 为 6 MB 的 OP `factory.bin`**，以及官方原厂固件 `JDCOS-JDC02`。
- 官方 ImmortalWrt 的 `sysupgrade.bin`(tar) 和 `initramfs-uImage.itb` **不能用**。
- **我们的 `squashfs-factory-*.bin` 就是 u-boot 能吃的格式**（约 78.5 MiB，别和"kernel 6 MB"混淆：
  6 MB 指 kernel 分区，整包尺寸可以更大）。
- u-boot webui：`/` = 固件（字段名 `firmware`）；`/img.html` = GPT/IMG（字段名 **`img`**）；
  `/art.html`、`/cdt.html`、`/uboot.html`。**写入成功 = 绿灯亮 3 秒。**
- 进 failsafe：**按住 reset 上电** → 红灯闪 5 次 → 变蓝 → webui 在 `192.168.1.1`。
- 若进不去 u-boot webui：把网卡速率手动改成 **10M 全双工**再试。

| 文件 | 用途 |
|---|---|
| `*-factory-*.bin` | 经 **u-boot webui** 刷（会清配置） |
| `*-sysupgrade-*.bin` | 已在 OpenWrt/ImmortalWrt 上，**系统内升级** |

## 9. 双 WAN 自动故障切换（mwan3）

### 9.1 两条 WAN

| 接口 | 设备 | 角色 | metric | mwan3 权重 |
|---|---|---|---|---|
| `wan` | `usb0`（手机 USB 共享 / RNDIS） | 主 | 10 | 20 |
| `waneth` | `wan`（物理网口） | 备 | 20 | 10 |

两个都在防火墙 `wan` zone 内（`masq=1`、`fullcone=1` 继承）。`wan6` 禁用（手机共享无 IPv6，IPv6 交给 mwan3）。

### 9.2 为什么需要 mwan3 而不是只靠 metric

**纯 metric 方案只能感知"链路断开"**：网线拔了、手机拔了，内核删除默认路由，另一条接管。
实测已验证这套机制有效：

```
两条路由并存 → ip route get 223.5.5.5 → via 192.168.11.1 dev usb0   （选 metric 小的）
删掉 usb0 路由 → ip route get 223.5.5.5 → via 192.168.99.1 dev wan    （自动接管）
```

**但它无法处理"网线插着、灯亮着、上游没网"** —— 物理链路是 UP 的，内核认为它好，不会切换。
这是公寓网络最常见的故障形态。

**mwan3 用定时 ping 健康探测补上这一环**：探测 `223.5.5.5` / `119.29.29.29` / `8.8.8.8`，
丢失率超阈值即把该线路标记为 down 并切换。配置在 `files/etc/config/mwan3`。

### 9.3 为什么要把 `wan=usb0` 烧成开机默认也是安全的

单看"WAN 必须用 usb0"很危险（没插手机就断网）。但**配上 mwan3 后不再危险**：
两条线路都由 mwan3 纳管，哪条健康走哪条，没插手机而网线通时自动走网线。

`files/etc/uci-defaults/99-ax6600-dualwan` 负责建立接口定义（幂等，已正确则不动）：

- `network.wan.device=usb0` / `proto=dhcp` / `metric=10`
- `network.waneth`（新建）= `wan` / `dhcp` / `metric=20`
- 把 `waneth` 加入防火墙 wan zone
- `network.wan6.disabled=1`

> ⚠️ 注意 `files/etc/config/mwan3` 会**覆盖** mwan3 包自带的默认配置。
> 如果你以后在 LuCI 里改了 mwan3 设置，下次刷机会被这里覆盖。

### 9.4 依赖

`mwan3` 依赖的 `ip-full`、`kmod-nf-conntrack-netlink`、`nftables` 本机已有；
`conntrack-tools` 会随本次构建一起编入。**kmod 都在，没有事后装不上的问题。**

## 10. storage 数据分区（226.8 GiB）

### 背景：上游的 `no-last-partition` 分区表把 226 GB 留在了 GPT 之外

实测发现磁盘 230.5 GiB，但 GPT 的 `last_usable` 只有 4.14 GiB：

```
mmcblk0 总容量          230.5 GiB
GPT last-usable           4.14 GiB
现有分区最大结束           3.69 GiB
表内剩余空闲              460 MiB
被漏掉的                 226.3 GiB
```

内核启动日志也报了不一致（主表有效但备份表过期）：

```
GPT:Primary header alternate_lba != Alt. header my_lba
GPT:8683519 != 483327999
GPT:last_usable_lbas don't match.  GPT:8683486 != 483327991
GPT:partition_entry_array_crc32 values don't match
```

**动手前先做了只读排查**（确认那 226 GB 没有活数据）：逐点采样 + `cmp` 与 `/dev/zero`
比对 + 检查 ext4/btrfs/f2fs 超级块位置 + 解析磁盘末尾的备份 GPT。结论：低段（4–64 GiB）
有旧残存、高段（100 GiB 以上）全零、**无任何有效文件系统**，可安全回收。

### 实际执行

```bash
sgdisk -b /root/gpt-before-storage.bin /dev/mmcblk0     # 先备份
sgdisk -e /dev/mmcblk0                                  # 扩展 GPT 到磁盘真实末尾
sgdisk -n 0:0:0 -c 0:storage -t 0:1B1720DA-A8BB-4B6F-92D2-0A93AB9609CA /dev/mmcblk0
mkfs.btrfs -L storage -f /dev/mmcblk0p27
```

结果：**`mmcblk0p27` = 226.8 GiB，btrfs，挂载在 `/mnt/storage`，200 MB 写入测试通过。**

开机自挂载由 `/etc/init.d/storage`（`S99storage`）负责，**不依赖 fstab**
（OpenWrt 的 fstab 由 `block-mount` 在启动早期读取，那时分区可能还没就绪，用 init 脚本更可靠）。

### ⚠️ 重要：这部分**不在固件里**

`storage` 分区与挂载脚本是**设备侧状态**：

- 分区表在 eMMC 上，**sysupgrade 会保留**；init 脚本在 `/etc/`（overlay），**也会保留**
- 但**刷 `factory.bin` 会清配置** → init 脚本没了，需要刷完重新创建（分区本身还在）

## 11. 刷完的待办

1. **改 WiFi 密码**（默认 `12345678` 是公开值）：
   ```bash
   for i in 0 1 2; do uci set wireless.default_radio$i.key='<新密码>'; done
   uci commit wireless && wifi reload
   ```
2. **配 netbird**（无 LuCI）：`netbird up --setup-key <后台生成的 setup key>`
3. **配 USB RNDIS WAN**：手机开「USB 共享网络」→ 出现 `usb0` →
   把 `network.wan` 的 device 指过去 + 配 firewall zone
4. **Samba / 备份 / git mirror**：Forgejo 直接放 **arm64 单文件**即可（不需要 Docker）
5. **eMMC 体检**：`mmc extcsd read /dev/mmcblk0 | grep -i life`

## 12. 已知坑

### 设备侧

- **绝对不要用 `apk add --force-broken-world`** — 会删掉 220 个包（内核 + kmod）把系统搞挂。
- **本机包管理器是 `apk`，不是 `opkg`**（新版 ImmortalWrt SNAPSHOT）。`opkg` 命令不存在。
- `/overlay`、`/opt/docker` 之类占位符**不能直接 `rm`**，要用 `mknod <path> c 0 0` 重建。
- `mmc-utils` 的**命令名是 `mmc`**（`/sbin/mmc`），不是 `mmc-utils`。
- BusyBox 精简，**没有 `od`、`blockdev`**；`hexdump` 可用。
- 写 shell 脚本时注意：`sh -c '... $(cat /path/$VAR/size) ...'` 这种嵌套在某些环境下
  `$VAR` 可能不展开，**用硬编码路径最稳**。

### 编译侧

- **kmod 必须随固件集成**，Release 不含独立 kmod。
- `make defconfig` 会静默丢弃 feeds 里不存在的包 → **必须用 `.manifest` 验证**。
- `WRT_PROFILE` 不能改名，只能 `PURE` / `PLUS`。
- 信道默认值**不在 `mac80211.uc`**，来自 DTS 生成的 `board.json`（见 §6.3）。

### 网络 / 传输

- **公司网络会 reset GitHub 的 https git 传输** → **用 SSH**（`git@github.com` 或 `ssh.github.com:443`）。
- 未认证 GitHub API 限流 **60 次/小时**。

## 13. 文档

| 文件 | 内容 |
|---|---|
| [`Docs/刷机救砖教程.md`](Docs/刷机救砖教程.md) | 开 SSH / 备份分区 / 刷 U-Boot / 9008 救砖 |
| `Config/GENERAL_AX6600_PLUS.txt` | 我们全部定制包的落点 |
| `Scripts/Settings.sh` | 默认值注入点（LAN IP / 主机名 / SSID / 密码 / 功率） |
| `files/etc/uci-defaults/99-ax6600-wifi` | 信道 + 功率 + 国家码兜底 |

## 14. 上游

| 仓库 | 关系 |
|---|---|
| [ones20250/Openwrt-AX6600](https://github.com/ones20250/Openwrt-AX6600) | 本仓库的 **fork 来源**，即 `origin` |
| [ones20250/immortalwrt_ipq](https://github.com/ones20250/immortalwrt_ipq) | **CI 编译时拉取的固件源码**（`QCA-ALL.yml` 的 `SOURCE` 矩阵），与 fork 关系无关 |

## 15. 免责声明

刷机有风险。本固件仅供自用与学习研究。请确认设备型号匹配，并提前备份数据。
