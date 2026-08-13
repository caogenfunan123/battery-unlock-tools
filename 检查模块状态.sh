#!/bin/sh
echo "═══════════════════════════════════════"
echo "      解锁模块状态检查"
echo "═══════════════════════════════════════"
echo ""

# 检查模块目录
echo "[1] 模块目录检查"
if [ -d "/data/adb/modules" ]; then
    echo "   ✅ /data/adb/modules 存在"
    echo ""
    echo "   已安装的模块:"
    for mod in /data/adb/modules/*/; do
        MODNAME=$(basename "$mod")
        PROP="$mod/module.prop"
        if [ -f "$PROP" ]; then
            NAME=$(grep "^name=" "$PROP" | cut -d= -f2)
            VER=$(grep "^version=" "$PROP" | cut -d= -f2)
            ENABLED="✅ 已启用"
            [ -f "${mod}disable" ] && ENABLED="❌ 已禁用"
            echo "   • $MODNAME ($NAME $VER) $ENABLED"
        else
            echo "   • $MODNAME (无module.prop)"
        fi
    done
else
    echo "   ❌ /data/adb/modules 不存在"
fi

# 检查JieSuoRong模块
echo ""
echo "[2] JieSuoRong模块详情"
JIE_PATH="/data/adb/modules/JieSuoRong"
if [ -d "$JIE_PATH" ]; then
    echo "   ✅ 模块目录存在"
    ls -la "$JIE_PATH/"
    echo ""
    echo "   module.prop内容:"
    cat "$JIE_PATH/module.prop" 2>/dev/null || echo "   无module.prop"
    echo ""
    echo "   service.sh内容:"
    cat "$JIE_PATH/service.sh" 2>/dev/null || echo "   无service.sh"
    echo ""
    echo "   run.log内容:"
    cat "$JIE_PATH/run.log" 2>/dev/null || echo "   无日志"
else
    echo "   ❌ 模块目录不存在"
fi

# 检查fake_cycle节点
echo ""
echo "[3] fake_cycle节点状态"
CYCLE_FILE="/sys/class/qcom-battery/fake_cycle"
if [ -f "$CYCLE_FILE" ]; then
    PERM=$(ls -la "$CYCLE_FILE" | awk '{print $1}')
    VAL=$(cat "$CYCLE_FILE" 2>/dev/null)
    echo "   ✅ 节点存在"
    echo "   权限: $PERM"
    echo "   当前值: $VAL"
    echo ""
    echo "   写入测试..."
    ORIG="$VAL"
    echo "0" > "$CYCLE_FILE" 2>/dev/null
    NEW=$(cat "$CYCLE_FILE" 2>/dev/null)
    if [ "$NEW" = "0" ]; then
        echo "   ✅ 可写入"
        echo "$ORIG" > "$CYCLE_FILE" 2>/dev/null
    else
        echo "   ❌ 写入失败（系统锁定）"
    fi
else
    echo "   ❌ 节点不存在"
fi

# 检查系统属性
echo ""
echo "[4] 系统属性检查"
if command -v getprop >/dev/null 2>&1; then
    CYCLE_PROP=$(getprop persist.battery.cycle 2>/dev/null)
    CAPACITY_PROP=$(getprop persist.battery.fake_capacity 2>/dev/null)
    REAL_PROP=$(getprop persist.battery.real_capacity 2>/dev/null)
    echo "   persist.battery.cycle: ${CYCLE_PROP:-未设置}"
    echo "   persist.battery.fake_capacity: ${CAPACITY_PROP:-未设置}"
    echo "   persist.battery.real_capacity: ${REAL_PROP:-未设置}"
else
    echo "   ⚠️  getprop不可用"
fi

echo ""
echo "═══════════════════════════════════════"
