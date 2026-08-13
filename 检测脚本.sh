#!/bin/sh
# 快速检测当前解锁状态
echo "═══════════════════════════════════════"
echo "      小米K60电池锁容状态检测"
echo "═══════════════════════════════════════"
echo ""

echo "📊 节点状态："
if [ -f /sys/class/qcom-battery/fake_cycle ]; then
    echo "   fake_cycle = $(cat /sys/class/qcom-battery/fake_cycle 2>/dev/null)"
else
    echo "   ❌ fake_cycle 节点不存在"
fi

if [ -f /sys/class/qcom-battery/fg1_fcc ]; then
    FCC=$(cat /sys/class/qcom-battery/fg1_fcc 2>/dev/null)
    FCC_MAH=$((FCC / 1000))
    echo "   fg1_fcc = ${FCC_MAH}mAh (目标: 6560mAh)"
else
    echo "   ❌ fg1_fcc 节点不存在"
fi

if [ -f /sys/class/qcom-battery/fg1_qmax ]; then
    QMAX=$(cat /sys/class/qcom-battery/fg1_qmax 2>/dev/null)
    echo "   fg1_qmax = ${QMAX}mAh (真实上限)"
else
    echo "   ❌ fg1_qmax 节点不存在"
fi

echo ""
echo "📱 系统上报容量："
if [ -f /sys/class/power_supply/battery/capacity ]; then
    CAP=$(cat /sys/class/power_supply/battery/capacity 2>/dev/null)
    echo "   电量 = ${CAP}%"
fi

if [ -f /sys/class/power_supply/battery/charge_full ]; then
    CF=$(cat /sys/class/power_supply/battery/charge_full 2>/dev/null)
    CF_MAH=$((CF / 1000))
    echo "   charge_full = ${CF_MAH}mAh"
fi

echo ""
echo "📦 Magisk模块状态："
if [ -d /data/adb/modules ]; then
    for mod in /data/adb/modules/*/; do
        MODNAME=$(basename "$mod")
        PROP="$mod/module.prop"
        if [ -f "$PROP" ]; then
            VER=$(grep "^version=" "$PROP" 2>/dev/null | cut -d= -f2)
            echo "   ✅ [$MODNAME] v$VER"
        else
            echo "   ✅ $MODNAME (无module.prop)"
        fi
    done
else
    echo "   ❌ /data/adb/modules 不存在"
fi

echo ""
echo "═══════════════════════════════════════"
