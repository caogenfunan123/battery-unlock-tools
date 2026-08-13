#!/bin/sh
echo "═══════════════════════════════════════"
echo "    小米K60电池锁容强制解锁脚本"
echo "═══════════════════════════════════════"
echo ""

# 检查root
if [ "$(id -u)" != "0" ]; then
    echo "❌ 需要Root权限"
    exit 1
fi

# 检查关键节点
echo "[1/5] 检查电池节点..."
if [ ! -d "/sys/class/qcom-battery" ]; then
    echo "   ❌ qcom-battery目录不存在"
    echo "   尝试其他路径..."
    for path in /sys/class/power_supply /sys/bus/tty; do
        if [ -d "$path" ]; then
            echo "   ✅ 找到: $path"
        fi
    done
fi

# 检查fake_cycle
if [ -f "/sys/class/qcom-battery/fake_cycle" ]; then
    echo "   ✅ fake_cycle存在"
    CURRENT_CYCLE=$(cat /sys/class/qcom-battery/fake_cycle 2>/dev/null)
    echo "   当前值: $CURRENT_CYCLE"
else
    echo "   ❌ fake_cycle不存在"
    # 尝试创建
    echo "   尝试创建节点..."
    mkdir -p /sys/class/qcom-battery 2>/dev/null
    if [ -f "/sys/class/qcom-battery/fake_cycle" ]; then
        echo "   ✅ 节点创建成功"
    else
        echo "   ❌ 无法创建节点，模块可能无效"
    fi
fi

# 检查fg1_fcc
echo ""
echo "[2/5] 检查FG芯片节点..."
if [ -f "/sys/class/qcom-battery/fg1_fcc" ]; then
    FCC_RAW=$(cat /sys/class/qcom-battery/fg1_fcc 2>/dev/null)
    FCC_MAH=$((FCC_RAW / 1000))
    echo "   ✅ fg1_fcc存在: ${FCC_MAH}mAh"
else
    echo "   ❌ fg1_fcc不存在"
fi

# 写入解锁值
echo ""
echo "[3/5] 执行解锁..."

# 方案1: 直接写入fake_cycle
if [ -w "/sys/class/qcom-battery/fake_cycle" ]; then
    echo "   → 写入fake_cycle=1..."
    echo "1" > /sys/class/qcom-battery/fake_cycle 2>/dev/null
    NEW_CYCLE=$(cat /sys/class/qcom-battery/fake_cycle 2>/dev/null)
    if [ "$NEW_CYCLE" = "1" ]; then
        echo "   ✅ fake_cycle已设置为1"
    else
        echo "   ❌ 写入失败，值: $NEW_CYCLE"
    fi
else
    echo "   ⚠️  fake_cycle只读，尝试chmod..."
    chmod 666 /sys/class/qcom-battery/fake_cycle 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "1" > /sys/class/qcom-battery/fake_cycle
        echo "   ✅ 写入成功"
    else
        echo "   ❌ 无法修改权限"
    fi
fi

# 方案2: 写入fg1_fcc（如果存在且可写）
if [ -f "/sys/class/qcom-battery/fg1_fcc" ] && [ -w "/sys/class/qcom-battery/fg1_fcc" ]; then
    echo "   → 写入fg1_fcc=6560000..."
    echo "6560000" > /sys/class/qcom-battery/fg1_fcc 2>/dev/null
    NEW_FCC=$(cat /sys/class/qcom-battery/fg1_fcc 2>/dev/null)
    NEW_FCC_MAH=$((NEW_FCC / 1000))
    if [ "$NEW_FCC_MAH" = "6560" ]; then
        echo "   ✅ fg1_fcc已设置为6560mAh"
    else
        echo "   ⚠️  写入值: ${NEW_FCC_MAH}mAh"
    fi
else
    echo "   ⚠️  fg1_fcc不可写或不存在"
fi

# 方案3: 写入charge_full
echo ""
echo "[4/5] 检查系统容量..."
if [ -f "/sys/class/power_supply/battery/charge_full" ]; then
    CF_RAW=$(cat /sys/class/power_supply/battery/charge_full 2>/dev/null)
    CF_MAH=$((CF_RAW / 1000))
    echo "   当前charge_full: ${CF_MAH}mAh"
    if [ $CF_MAH -lt 6000 ]; then
        echo "   → 尝试更新charge_full..."
        echo "6560000" > /sys/class/power_supply/battery/charge_full 2>/dev/null
        NEW_CF=$(cat /sys/class/power_supply/battery/charge_full 2>/dev/null)
        NEW_CF_MAH=$((NEW_CF / 1000))
        echo "   更新后: ${NEW_CF_MAH}mAh"
    fi
fi

# 方案4: 系统属性
echo ""
echo "[5/5] 设置系统属性..."
if command -v setprop >/dev/null 2>&1; then
    setprop persist.battery.cycle 1
    setprop persist.battery.fake_capacity 6560
    setprop persist.battery.real_capacity 6560000
    echo "   ✅ 系统属性已设置"
else
    echo "   ⚠️  setprop不可用"
fi

# 验证结果
echo ""
echo "═══════════════════════════════════════"
echo "              验证结果"
echo "═══════════════════════════════════════"
echo ""
echo "当前状态："
if [ -f "/sys/class/qcom-battery/fake_cycle" ]; then
    echo "   fake_cycle: $(cat /sys/class/qcom-battery/fake_cycle)"
fi
if [ -f "/sys/class/qcom-battery/fg1_fcc" ]; then
    FCC_VAL=$(cat /sys/class/qcom-battery/fg1_fcc)
    echo "   fg1_fcc: $((FCC_VAL / 1000))mAh"
fi
if [ -f "/sys/class/power_supply/battery/charge_full" ]; then
    CF_VAL=$(cat /sys/class/power_supply/battery/charge_full)
    echo "   charge_full: $((CF_VAL / 1000))mAh"
fi
echo ""
echo "═══════════════════════════════════════"
echo ""
echo "💡 下一步操作："
echo "   1. 如果以上都成功了，重启手机让系统重新读取"
echo "   2. 如果fake_cycle写入失败，说明硬件锁定，需要装模块"
echo "   3. 检查Magisk/KernelSU模块是否启用"
echo ""
echo "是否需要重启？(y/n)"
read -t 10 RESTART
if [ "$RESTART" = "y" ] || [ "$RESTART" = "Y" ]; then
    reboot
fi
