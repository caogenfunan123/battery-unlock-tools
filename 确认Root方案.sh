#!/bin/sh
echo "═══════════════════════════════════════"
echo "      Root方案诊断工具"
echo "═══════════════════════════════════════"
echo ""

# su检查
echo "[1] su二进制检查"
for path in /sbin/su /system/bin/su /system/xbin/su /vendor/bin/su /usr/bin/su /data/local/bin/su; do
    if [ -f "$path" ]; then
        echo "   ✅ 找到: $path"
        ls -la "$path" | awk '{print "      权限:"$1" 大小:"$5"字节"}'
        
        # 检查版本
        if [ -x "$path" ]; then
            VERSION=$("$path" --version 2>/dev/null || "$path" -V 2>/dev/null || echo "未知")
            echo "      版本: $VERSION"
        fi
    fi
done
echo ""

# Magisk检查
echo "[2] Magisk检查"
if command -v magisk >/dev/null 2>&1; then
    MAGISK_VER=$(magisk -v 2>/dev/null || echo "未知")
    echo "   ✅ Magisk已安装: $MAGISK_VER"
    echo "   路径: $(which magisk)"
else
    echo "   ❌ Magisk未找到"
fi

# 检查Magisk模块目录
if [ -d "/data/adb/modules" ]; then
    echo "   ✅ Magisk模块目录存在: /data/adb/modules"
    MODULE_COUNT=$(ls -1 /data/adb/modules/ 2>/dev/null | wc -l | tr -d ' ')
    echo "   已安装模块数: $MODULE_COUNT"
else
    echo "   ❌ /data/adb/modules 不存在"
fi
echo ""

# KernelSU检查
echo "[3] KernelSU检查"
KSU_FOUND=0
if [ -f "/data/adb/ksud" ]; then
    echo "   ✅ ksud存在: /data/adb/ksud"
    KSU_FOUND=1
fi
if [ -d "/data/adb/ksu" ]; then
    echo "   ✅ ksu目录存在: /data/adb/ksu"
    KSU_FOUND=1
fi
if command -v ksud >/dev/null 2>&1; then
    echo "   ✅ ksud命令可用"
    KSU_FOUND=1
fi

# 检查KSU模块目录
if [ -d "/data/adb/ksu/modules" ]; then
    echo "   ✅ KSU模块目录存在: /data/adb/ksu/modules"
    MODULE_COUNT=$(ls -1 /data/adb/ksu/modules/ 2>/dev/null | wc -l | tr -d ' ')
    echo "   已安装模块数: $MODULE_COUNT"
    KSU_FOUND=1
fi

if [ $KSU_FOUND -eq 0 ]; then
    echo "   ❌ 未检测到KernelSU"
fi
echo ""

# 进程检查
echo "[4] 后台进程检查"
echo "   Magisk相关:"
ps -A 2>/dev/null | grep -iE "magisk|supersu" | grep -v grep | head -3 || echo "      未检测到"
echo "   KernelSU相关:"
ps -A 2>/dev/null | grep -iE "ksud|kernelSU" | grep -v grep | head -3 || echo "      未检测到"
echo ""

# 结论
echo "═══════════════════════════════════════"
echo "              诊断结论"
echo "═══════════════════════════════════════"
echo ""

if [ -d "/data/adb/ksu/modules" ] && [ ! -d "/data/adb/modules" ]; then
    echo "✅ 你使用的是: KernelSU"
    echo ""
    echo "解锁方案："
    echo "1. 将模块解压到 /data/adb/ksu/modules/"
    echo "2. 运行: sh /storage/emulated/0/电池/安装舟版模块.sh"
elif [ -d "/data/adb/modules" ] && [ ! -d "/data/adb/ksu/modules" ]; then
    echo "✅ 你使用的是: Magisk"
    echo ""
    echo "解锁方案："
    echo "1. 在Magisk App中装入模块zip文件"
    echo "2. 或手动解压到 /data/adb/modules/"
else
    echo "⚠️  检测到混合环境，需要进一步诊断"
fi

echo ""
echo "═══════════════════════════════════════"
echo "立即运行解锁脚本？(y/n)"
read -t 10 ANSWER
if [ "$ANSWER" = "y" ] || [ "$ANSWER" = "Y" ]; then
    echo "正在运行解锁脚本..."
    sh /storage/emulated/0/电池/安装舟版模块_v2.sh
fi
