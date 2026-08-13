#!/bin/sh
echo "═══════════════════════════════════════"
echo "      舟版电池模拟器安装脚本 v2"
echo "═══════════════════════════════════════"
echo ""

if [ "$(id -u)" != "0" ]; then
    echo "❌ 需要Root权限"
    exit 1
fi

# 源文件位置
SRC_ZIP="/storage/emulated/0/电池/舟版解容模块-1.6.2.zip"
MODPATH="/data/adb/modules/battery-simulator"

echo "[1/5] 清理旧安装..."
if [ -d "$MODPATH" ]; then
    rm -rf "$MODPATH"
    echo "   ✅ 已清理旧模块"
fi

echo "[2/5] 解压模块..."
unzip -o "$SRC_ZIP" -d "$MODPATH" 2>/dev/null
if [ $? -ne 0 ]; then
    echo "   ❌ 解压失败"
    exit 1
fi
echo "   ✅ 解压完成"

echo "[3/5] 设置权限..."
chmod +x "$MODPATH/service.sh"
chmod +x "$MODPATH/system/bin/battery_simulator"
chmod +x "$MODPATH/system/bin/battery_current_monitor"
chmod +x "$MODPATH/system/bin/dclog"
chown -R root:root "$MODPATH"
echo "   ✅ 权限设置完成"

echo "[4/5] 清理可能冲突的文件..."
# 删除可能存在的锁定文件
rm -f /data/local/tmp/.battery_simulate.lock
rm -f /data/local/tmp/.battery_service.pid
rm -f /sys/class/qcom-battery/fake_cycle.lock
echo "   ✅ 冲突文件已清理"

echo "[5/5] 验证安装..."
echo "   模块目录: $MODPATH"
ls -la "$MODPATH/" | grep -E "service.sh|module.prop"
echo ""
echo "   可执行文件:"
ls -la "$MODPATH/system/bin/" | grep -E "battery|dclog"

echo ""
echo "═══════════════════════════════════════"
echo "           安装完成！"
echo "═══════════════════════════════════════"
echo ""
echo "⚠️  重要：必须重启手机！"
echo ""
echo "重启后步骤："
echo "1. 等待手机完全启动（约2分钟）"
echo "2. 运行检测脚本验证"
echo "   sh /storage/emulated/0/电池/检测脚本.sh"
echo ""
echo "如果容量仍未恢复："
echo "1. 检查服务是否运行："
echo "   ps | grep battery_simulator"
echo ""
echo "2. 查看日志："
echo "   cat /data/local/tmp/battery_service.log | tail -20"
echo ""
echo "立即重启？(y/n，10秒超时)"
read -t 10 RESTART
if [ "$RESTART" = "y" ] || [ "$RESTART" = "Y" ]; then
    echo "正在重启系统..."
    reboot
fi
