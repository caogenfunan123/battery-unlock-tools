#!/bin/sh
echo "═══════════════════════════════════════"
echo "      KernelSU & Root 状态诊断工具"
echo "═══════════════════════════════════════"
echo ""

# 检查基础权限
echo "[1] 用户权限检查"
echo "   whoami: $(whoami)"
echo "   UID: $(id -u)"
echo "   GID: $(id -g)"
echo "    groups: $(id -G)"
echo ""

# 检查su二进制文件
echo "[2] su二进制文件检查"
for path in /sbin/su /system/bin/su /system/xbin/su /vendor/bin/su /usr/bin/su /data/local/bin/su; do
    if [ -f "$path" ]; then
        echo "   ✅ 找到: $path"
        ls -la "$path"
    fi
done

# 检查KernelSU核心组件
echo ""
echo "[3] KernelSU核心组件检查"
if [ -f "/data/adb/ksud" ]; then
    echo "   ✅ 存在: /data/adb/ksud"
    ls -la /data/adb/ksud
fi
if [ -d "/data/adb/ksu" ]; then
    echo "   ✅ 存在: /data/adb/ksu"
    ls -la /data/adb/ksu
fi
if [ -f "/sbin/.kerneldebugd" ]; then
    echo "   ✅ 存在: /sbin/.kerneldebugd"
fi

# 检查内核版本
echo ""
echo "[4] 内核信息"
echo "   $(uname -a 2>/dev/null || cat /proc/version 2>/dev/null)"
echo ""
KERNEL_VER=$(grep -oE '[0-9]+\.[0-9]+\.[0-9]+' /proc/version 2>/dev/null | head -1)
echo "   内核版本: ${KERNEL_VER:-未知}"

# 检查sysfs节点
echo ""
echo "[5] 电池节点检查"
for node in fake_cycle fg1_fcc fg1_qmax charge_full; do
    path="/sys/class/qcom-battery/$node"
    if [ -f "$path" ]; then
        PERM=$(ls -la "$path" 2>/dev/null | awk '{print $1}')
        VAL=$(cat "$path" 2>/dev/null)
        echo "   ✅ $node"
        echo "      权限: $PERM"
        echo "      值: $VAL"
    else
        echo "   ❌ $node 不存在"
    fi
done

# 写入测试
echo ""
echo "[6] 写入权限测试"
if [ -w "/sys/class/qcom-battery/fake_cycle" ]; then
    echo "   ✅ fake_cycle 可写"
    ORIG=$(cat /sys/class/qcom-battery/fake_cycle)
    echo "   写入 0..."
    echo "0" > /sys/class/qcom-battery/fake_cycle
    NEW=$(cat /sys/class/qcom-battery/fake_cycle)
    echo "   写入后值: $NEW"
    if [ "$NEW" = "0" ]; then
        echo "   ✅ 写入成功！"
    else
        echo "   ❌ 写入被系统锁定"
    fi
    echo "$ORIG" > /sys/class/qcom-battery/fake_cycle
else
    echo "   ❌ fake_cycle 不可写"
fi

if [ -w "/sys/class/qcom-battery/fg1_fcc" ]; then
    echo "   ✅ fg1_fcc 可写"
else
    echo "   ❌ fg1_fcc 不可写"
fi

# 检查是否有binder支持
echo ""
echo "[7] Binder IPC检查"
if [ -c "/dev/binder" ]; then
    echo "   ✅ /dev/binder 存在"
else
    echo "   ⚠️  /dev/binder 不存在"
fi

# 最终结论
echo ""
echo "═══════════════════════════════════════"
echo "              诊断结论"
echo "═══════════════════════════════════════"
if [ -d "/data/adb/ksu" ]; then
    echo "✅ KernelSU已正确安装"
    echo ""
    echo "解锁步骤："
    echo "1. 将模块复制到: /data/adb/modules/"
    echo "2. 重启手机"
    echo "3. 运行检测脚本验证"
elif [ ! -d "/data/adb/ksu" ] && [ ! -f "/data/adb/ksud" ]; then
    echo "❌ 未检测到KernelSU"
    echo ""
    echo "可能情况："
    echo "- 使用的是其他Root方案（Magisk/APatch等）"
    echo "- Root环境不完整"
    echo ""
    echo "建议："
    echo "1. 打开你的Root管理器App"
    echo "2. 确认Root状态"
    echo "3. 如果显示KernelSU但目录不存在，需要重新安装"
fi
echo "═══════════════════════════════════════"
