#!/bin/sh
echo "═══════════════════════════════════════"
echo "    KernelSU 电池锁容一键解容工具"
echo "═══════════════════════════════════════"
echo ""

# 检查Root
if [ "$(id -u)" != "0" ]; then
    echo "❌ 需要Root权限"
    exit 1
fi

# 读取当前状态
echo "[1/6] 读取当前状态..."
FAKE_CYCLE=$(cat /sys/class/qcom-battery/fake_cycle 2>/dev/null || echo "0")
FG1_FCC=$(cat /sys/class/qcom-battery/fg1_fcc 2>/dev/null)
FG1_QMAX=$(cat /sys/class/qcom-battery/fg1_qmax 2>/dev/null)
CHARGE_FULL=$(cat /sys/class/power_supply/battery/charge_full 2>/dev/null)

echo "   fake_cycle: $FAKE_CYCLE"
echo "   fg1_fcc: ${FG1_FCC:-未知}"
echo "   fg1_qmax: ${FG1_QMAX:-未知}"
echo "   charge_full: ${CHARGE_FULL:-未知}"
echo ""

# 目标值
TARGET_FCC=6560000
TARGET_CYCLE=1

echo "[2/6] 尝试解锁方法..."

# 方法1: 直接写入fake_cycle
echo "   → 写入 fake_cycle=$TARGET_CYCLE"
echo "$TARGET_CYCLE" > /sys/class/qcom-battery/fake_cycle 2>/dev/null
if [ $? -eq 0 ] && [ "$(cat /sys/class/qcom-battery/fake_cycle)" = "$TARGET_CYCLE" ]; then
    echo "   ✅ fake_cycle 写入成功"
else
    echo "   ❌ fake_cycle 写入失败或被子系统锁定"
fi

# 方法2: 尝试写入fg1_fcc（如果可写）
if [ -w /sys/class/qcom-battery/fg1_fcc ]; then
    echo "   → 写入 fg1_fcc=$TARGET_FCC"
    echo "$TARGET_FCC" > /sys/class/qcom-battery/fg1_fcc 2>/dev/null
    if [ $? -eq 0 ]; then
        NEW_FCC=$(cat /sys/class/qcom-battery/fg1_fcc)
        MAH=$((NEW_FCC / 1000))
        echo "   ✅ fg1_fcc 已设置为 ${MAH}mAh"
    else
        echo "   ❌ fg1_fcc 写入失败"
    fi
else
    echo "   ⚠️  fg1_fcc 不可写"
fi

echo ""
echo "[3/6] 修改系统属性..."
# 写入持久化属性
setprop persist.battery.cycle $TARGET_CYCLE 2>/dev/null
setprop persist.battery.fake_capacity 6560 2>/dev/null
setprop persist.battery.real_capacity $TARGET_FCC 2>/dev/null
setprop persist.vendor.battery.capacity 6560 2>/dev/null
echo "   ✅ 系统属性已设置"

# 写入属性文件（如果可能）
if [ -d "/data/property" ]; then
    echo "persist.battery.cycle=$TARGET_CYCLE" > /data/property/persist.battery.cycle 2>/dev/null
    echo "persist.battery.fake_capacity=6560" > /data/property/persist.battery.fake_capacity 2>/dev/null
    echo "persist.battery.real_capacity=$TARGET_FCC" > /data/property/persist.battery.real_capacity 2>/dev/null
    echo "   ✅ 属性文件已写入"
else
    echo "   ⚠️  /data/property 不存在"
fi

echo ""
echo "[4/6] 禁用电池管理服务..."
# 尝试禁用MIUI电池服务
pm disable com.miui.securitycenter/com.miui.powercenter.provider.PowerSaveService 2>/dev/null && echo "   ✅ 已禁用 PowerSaveService" || echo "   ⚠️  PowerSaveService禁用失败"
pm disable com.miui.powerkeeper 2>/dev/null && echo "   ✅ 已禁用 powerkeeper" || echo "   ⚠️  powerkeeper禁用失败"

echo ""
echo "[5/6] 清理可能的锁定文件..."
rm -f /sys/class/qcom-battery/fake_cycle.lock
rm -f /sys/class/qcom-battery/fg1_fcc.lock
rm -f /data/local/tmp/.battery_simulate.lock
echo "   ✅ 锁定文件已清理"

echo ""
echo "[6/6] 最终验证..."
echo ""
echo "   当前状态："
echo "   - fake_cycle: $(cat /sys/class/qcom-battery/fake_cycle 2>/dev/null)"
echo "   - fg1_fcc: $(( $(cat /sys/class/qcom-battery/fg1_fcc 2>/dev/null) / 1000 ))mAh"
echo "   - charge_full: $(( $(cat /sys/class/power_supply/battery/charge_full 2>/dev/null) / 1000 ))mAh"
echo "   - 电量: $(cat /sys/class/power_supply/battery/capacity 2>/dev/null)%"

echo ""
echo "═══════════════════════════════════════"
echo "           解锁完成！"
echo "═══════════════════════════════════════"
echo ""
echo "⚠️  必须重启手机才能生效！"
echo ""
echo "重启后运行检测脚本验证："
echo "sh /storage/emulated/0/电池/检测脚本.sh"
echo ""
echo "立即重启？(y/n)"
read RESTART
if [ "$RESTART" = "y" ] || [ "$RESTART" = "Y" ]; then
    echo "正在重启..."
    reboot
fi
