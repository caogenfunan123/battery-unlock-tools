#!/bin/sh
echo "═══════════════════════════════════════"
echo "    禁用MIUI电池服务 · 强制解锁脚本"
echo "═══════════════════════════════════════"
echo ""

# 检查权限
if [ "$(id -u)" != "0" ]; then
    echo "❌ 需要Root权限"
    exit 1
fi

echo "[1/5] 备份当前状态..."
ORIG_FAKE_CYCLE=$(cat /sys/class/qcom-battery/fake_cycle 2>/dev/null || echo "未知")
ORIG_FCC=$(cat /sys/class/qcom-battery/fg1_fcc 2>/dev/null || echo "未知")
echo "   原始fake_cycle: $ORIG_FAKE_CYCLE"
echo "   原始fg1_fcc: $ORIG_FCC"
echo ""

echo "[2/5] 禁用MIUI电池管理服务..."
# 方法1: 禁用PowerSaveService
pm disable com.miui.securitycenter/com.miui.powercenter.provider.PowerSaveService 2>/dev/null
if [ $? -eq 0 ]; then
    echo "   ✅ 已禁用 PowerSaveService"
else
    echo "   ⚠️  PowerSaveService禁用失败"
fi

# 方法2: 禁用battery manager
pm disable com.android.batterystats 2>/dev/null
pm disable com.miui.powerkeeper 2>/dev/null
echo "   → 已禁用 batterystats 和 powerkeeper"
echo ""

echo "[3/5] 强制写入解锁节点..."
# 写入fake_cycle
echo "1" > /sys/class/qcom-battery/fake_cycle 2>/dev/null
if [ $? -eq 0 ]; then
    VAL=$(cat /sys/class/qcom-battery/fake_cycle 2>/dev/null)
    if [ "$VAL" = "1" ]; then
        echo "   ✅ fake_cycle = 1"
    else
        echo "   ❌ fake_cycle 写入后被系统覆盖为: $VAL"
    fi
else
    echo "   ❌ fake_cycle 写入失败"
fi

# 尝试写入fg1_fcc（如果可以写的话）
if [ -w /sys/class/qcom-battery/fg1_fcc ]; then
    echo "6560000" > /sys/class/qcom-battery/fg1_fcc 2>/dev/null
    VAL=$(cat /sys/class/qcom-battery/fg1_fcc 2>/dev/null)
    MAH=$((VAL / 1000))
    echo "   fg1_fcc = ${MAH}mAh"
else
    echo "   ⚠️  fg1_fcc 不可写"
fi
echo ""

echo "[4/5] 设置系统属性..."
setprop persist.battery.cycle 1 2>/dev/null
setprop persist.battery.fake_capacity 6560 2>/dev/null
setprop persist.battery.real_capacity 6560000 2>/dev/null
echo "   ✅ 系统属性已设置"
echo ""

echo "[5/5] 重置电池缓存..."
dumpsys battery reset 2>/dev/null
echo "   ✅ 电池缓存已重置"
echo ""

echo "═══════════════════════════════════════"
echo "              执行完成"
echo "═══════════════════════════════════════"
echo ""
echo "💡 重要：必须重启手机才能让所有更改生效！"
echo ""
echo "重启后检查："
echo "1. 运行检测脚本查看容量是否恢复"
echo "2. 如果还是锁容，可能需要重新刷KernelSU"
echo ""
echo "立即重启？(y/n)"
read -t 10 RESTART
if [ "$RESTART" = "y" ] || [ "$RESTART" = "Y" ]; then
    echo "正在重启..."
    reboot
fi
