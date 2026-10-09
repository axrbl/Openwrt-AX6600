#!/bin/bash

apply_sed_to_matches() {
	local SEARCH_DIR=$1
	local FILE_NAME=$2
	local SED_EXPR=$3
	local MATCHES

	MATCHES=$(find "$SEARCH_DIR" -type f -name "$FILE_NAME" 2>/dev/null)
	if [ -n "$MATCHES" ]; then
		while IFS= read -r TARGET_FILE; do
			sed -i "$SED_EXPR" "$TARGET_FILE"
		done <<< "$MATCHES"
	fi
}

#移除luci-app-attendedsysupgrade
apply_sed_to_matches "./feeds/luci/collections/" "Makefile" "/attendedsysupgrade/d"

#修改默认主题
#sed -i "s/luci-theme-bootstrap/luci-theme-$WRT_THEME/g" $(find ./feeds/luci/collections/ -type f -name "Makefile")
#sed -i "s/luci-theme-.*$/luci-theme-bootstrap/g" $(find ./feeds/luci/collections/ -type f -name "Makefile")

#修改immortalwrt.lan关联IP
apply_sed_to_matches "./feeds/luci/modules/luci-mod-system/" "flash.js" "s/192\\.168\\.[0-9]*\\.[0-9]*/$WRT_IP/g"
#添加编译日期标识
apply_sed_to_matches "./feeds/luci/modules/luci-mod-status/" "10_system.js" "s/(\\(luciversion || ''\\))/(\\1) + (' \\/ $WRT_MARK-$WRT_DATE')/g"

WIFI_SH=$(find ./target/linux/{mediatek/filogic,qualcommax}/base-files/etc/uci-defaults/ -type f -name "*set-wireless.sh" 2>/dev/null)
WIFI_UC="./package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc"
if [ -f "$WIFI_SH" ]; then
	#修改WIFI名称
	sed -i "s/BASE_SSID='.*'/BASE_SSID='$WRT_SSID'/g" "$WIFI_SH"
	#修改WIFI密码
	sed -i "s/BASE_WORD='.*'/BASE_WORD='$WRT_WORD'/g" "$WIFI_SH"
fi

# =========================================================
# 无线默认值补丁（本 fork 新增）
# 上游把 5G-1 的默认信道设成 100，但本机 phy0 实测禁用 36-144（仅 149-165
# 可用），导致 AP 直接启动失败：hostapd 报 "Hardware does not support
# configured channel" / "not allowed for AP mode"，5G-1 射频完全不工作。
# 同时上游从未设置发射功率，驱动默认值高达 24-27 dBm，对 20 平单间严重过量。
# =========================================================
WIFI_UC=""
for CAND in \
	"./package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc" \
	"./package/network/config/wifi-scripts/files/lib/wifi/mac80211.sh" \
	"./package/kernel/mac80211/files/lib/wifi/mac80211.sh" ; do
	[ -f "$CAND" ] && WIFI_UC="$CAND" && break
done
if [ -z "$WIFI_UC" ]; then
	WIFI_UC=$(find ./package -type f -name 'mac80211.uc' 2>/dev/null | head -n 1)
fi

if [ -n "$WIFI_UC" ] && [ -f "$WIFI_UC" ]; then
	echo "Wireless defaults patch target: $WIFI_UC"

	# --- 国家码 ---
	if grep -q "country || 'CN'" "$WIFI_UC" 2>/dev/null; then
		sed -i "s/country || 'CN'/country || '$WRT_COUNTRY'/g" "$WIFI_UC"
		echo "  country default -> $WRT_COUNTRY  OK"
	else
		echo "  WARN: \"country || 'CN'\" 未找到，国家码未打补丁"
	fi

	# --- 发射功率 ---
	# 上游【完全没有】txpower 这一项，驱动会用自身默认值（实测 24-27 dBm，
	# 对 20 平单间严重过量）。在 channel 行之后插入。
	if grep -q 'txpower' "$WIFI_UC" 2>/dev/null; then
		echo "  txpower 已存在，跳过"
	elif grep -q 'set ${s}.channel' "$WIFI_UC" 2>/dev/null; then
		sed -i "/set \${s}\.channel=/a set \${s}.txpower='$WRT_TXPOWER'" "$WIFI_UC"
		echo "  txpower 已插入: $WRT_TXPOWER dBm  OK"
	else
		echo "  WARN: 未找到 channel 行，txpower 未插入"
	fi

	# --- SSID / 密码（上游是硬编码字面量） ---
	if grep -q "ssid='OWRT'" "$WIFI_UC" 2>/dev/null; then
		sed -i "s/ssid='OWRT'/ssid='$WRT_SSID'/g" "$WIFI_UC"
		echo "  ssid -> $WRT_SSID  OK"
	else
		echo "  WARN: ssid='OWRT' 未找到"
	fi
	if grep -q "key='12345678'" "$WIFI_UC" 2>/dev/null; then
		sed -i "s/key='12345678'/key='$WRT_WORD'/g" "$WIFI_UC"
		echo "  key -> (已设置)  OK"
	else
		echo "  WARN: key='12345678' 未找到"
	fi
	sed -i "s/encryption='none'/encryption='psk2+ccmp'/g" "$WIFI_UC"

	echo "  --- 打补丁后的关键行 ---"
	grep -nE "country \|\||txpower|ssid=|key=" "$WIFI_UC" | sed 's/^/    /'

	# --- 默认信道 ---
	# 信道采用 ACS（auto）+ 白名单，由 files/etc/uci-defaults/99-ax6600-wifi
	# 在首次启动时设定，这里【不】替换 default_channel。
	# 原因：本机 phy0 的 default_channel 是 100（错的，phy0 禁用 36-144），
	# 但改成任何固定值都不如"auto + 白名单"——后者能自动避开拥挤，
	# 而白名单保证不会选到信道 14（2.4G，只能跑 802.11b，AP 会宕机）
	# 或 DFS 信道（5G 低段 52-64，要 60s CAC 且会被雷达踢下线）。
	echo "  NOTE: 信道策略 = ACS auto + 白名单，交由 uci-defaults/99-ax6600-wifi 设定"
else
	echo "ERROR: mac80211.uc/sh not found - wireless defaults NOT patched!"
fi

CFG_FILE="./package/base-files/files/bin/config_generate"
#修改默认IP地址
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" "$CFG_FILE"
#修改默认主机名
sed -i "s/hostname='.*'/hostname='$WRT_NAME'/g" "$CFG_FILE"

#配置文件修改
echo "CONFIG_PACKAGE_luci=y" >> ./.config
echo "CONFIG_LUCI_LANG_zh_Hans=y" >> ./.config
#echo "CONFIG_PACKAGE_luci-theme-$WRT_THEME=y" >> ./.config
#echo "CONFIG_PACKAGE_luci-app-$WRT_THEME-config=y" >> ./.config

#手动调整的插件
if [ -n "$WRT_PACKAGE" ]; then
	echo -e "$WRT_PACKAGE" >> ./.config
fi

#高通平台调整
DTS_PATH="./target/linux/qualcommax/dts/"
if [[ "${WRT_TARGET^^}" == *"QUALCOMMAX"* ]]; then
	#无WIFI配置调整Q6大小
	if [[ "${WRT_CONFIG,,}" == *"wifi"* && "${WRT_CONFIG,,}" == *"no"* ]]; then
		find "$DTS_PATH" -type f ! -iname '*nowifi*' -exec sed -i 's/ipq\(6018\|8074\).dtsi/ipq\1-nowifi.dtsi/g' {} +
		echo "qualcommax set up nowifi successfully!"
	fi
fi

# =========================================================
# 智能系统调优：优化内存水位线 (min_free_kbytes)
# =========================================================

MIN_FREE_VAL=16384
CONF_FILE="./package/base-files/files/etc/sysctl.conf"

# 提取当前值（只匹配非注释、行首）
CURRENT_VAL=$(sed -n 's/^vm\.min_free_kbytes=\([0-9]\+\).*/\1/p' "$CONF_FILE")

if [ -z "$CURRENT_VAL" ]; then
    echo "" >> "$CONF_FILE"
    echo "vm.min_free_kbytes=$MIN_FREE_VAL" >> "$CONF_FILE"
    echo "Memory patch: value not found, added $MIN_FREE_VAL."
else
    if [ "$CURRENT_VAL" -lt "$MIN_FREE_VAL" ]; then
        sed -i "s/^vm\.min_free_kbytes=.*/vm.min_free_kbytes=$MIN_FREE_VAL/" "$CONF_FILE"
        echo "Memory patch: upgraded $CURRENT_VAL -> $MIN_FREE_VAL."
    else
        echo "Memory patch: current value ($CURRENT_VAL) is sufficient, skipped."
    fi
fi
