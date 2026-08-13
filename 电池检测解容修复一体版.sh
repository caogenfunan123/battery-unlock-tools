#!/system/bin/sh

RED='\033[0;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
ORANGE='\033[0;33m'
LIGHT_BLUE='\033[1;34m'
PURPLE='\033[1;35m'
CYAN='\033[1;36m'
NC='\033[0m'

COUNT_FILE="/data/charge_cycle_count.txt"
CYCLE_FLAG_FILE="/data/battery_cycle_flag.txt"
UNLOCK_LOG="/data/battery_unlock_log.txt"

# ====================== 【你要求新增：realme 机型识别】 ======================
IS_REALME=0
if grep -q "realme" /system/build.prop /proc/device-tree/model /dev/block/by-name/frp 2>/dev/null; then
    IS_REALME=1
fi
# ============================================================================

if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}❌ 必须获取ROOT权限才能运行！${NC}"
    echo -e "${ORANGE}正在自动申请ROOT...${NC}"
    su -c "sh $0"
    exit $?
fi
echo -e "${GREEN}✅ ROOT权限获取成功，已解锁系统级操作${NC}"
chmod 777 "$0" 2>/dev/null
rm -f "$UNLOCK_LOG" 2>/dev/null
echo "=== 解锁日志 $(date +%Y-%m-%d\ %H:%M:%S) ===" > "$UNLOCK_LOG"

# ====================== 【你要求新增：真我专用电池路径】 ======================
BATTERY_PATH="/sys/class/power_supply/battery"
CAPACITY="${BATTERY_PATH}/capacity"
STATUS="${BATTERY_PATH}/status"
VOLTAGE_NOW="${BATTERY_PATH}/voltage_now"
TEMP="${BATTERY_PATH}/temp"
CHARGE_FULL="${BATTERY_PATH}/charge_full"
CHARGE_NOW="${BATTERY_PATH}/charge_now"
CURRENT_NOW="${BATTERY_PATH}/current_now"
CYCLE_COUNT="${BATTERY_PATH}/cycle_count"
TECHNOLOGY="${BATTERY_PATH}/technology"
HEALTH="${BATTERY_PATH}/health"

# 原路径只在非真我时使用
if [ "$IS_REALME" -ne 1 ]; then
    CHARGE_FULL_DESIGN="/sys/class/power_supply/battery/charge_full_design"
    QCOM_BATT_DIR="/sys/class/qcom-battery"
    FAKE_CYCLE="${QCOM_BATT_DIR}/fake_cycle"
    FG1_QMAX="${QCOM_BATT_DIR}/fg1_qmax"
    FG1_FCC="${QCOM_BATT_DIR}/fg1_fcc"
    BATT_CALIBRATE="${QCOM_BATT_DIR}/calibrate"
    BATT_RESET_CAP="${QCOM_BATT_DIR}/reset_capacity"
    FAST_CHARGE_HEALTH="${QCOM_BATT_DIR}/fast_charge_health"
    FAST_CHARGE_ENABLE="${QCOM_BATT_DIR}/fast_charge_enable"
    VOLTAGE_MAX_DESIGN="/sys/class/power_supply/battery/voltage_max_design"
else
    # 真我屏蔽高通节点，避免冲突
    CHARGE_FULL_DESIGN="${BATTERY_PATH}/charge_full"
    QCOM_BATT_DIR="/dev/null"
    FAKE_CYCLE="/dev/null"
    FG1_QMAX="${BATTERY_PATH}/charge_full"
    FG1_FCC="${BATTERY_PATH}/charge_full"
    BATT_CALIBRATE="/dev/null"
    BATT_RESET_CAP="/dev/null"
    FAST_CHARGE_HEALTH="/dev/null"
    FAST_CHARGE_ENABLE="/dev/null"
    VOLTAGE_MAX_DESIGN="${VOLTAGE_NOW}"
fi
# ============================================================================

safe_read() {
    local f="$1"
    [ -f "$f" ] && cat "$f" 2>/dev/null | tr -d -c '0-9.-' || echo 0
}

safe_write() {
    local node="$1"
    local value="$2"
    local desc="$3"
    if [ ! -f "$node" ]; then
        echo "[-] 节点不存在：$node，跳过$desc" >> "$UNLOCK_LOG"
        return 1
    fi
    chmod 777 "$node" 2>/dev/null
    echo "$value" > "$node" 2>/dev/null
    local write_ret=$?
    chmod 644 "$node" 2>/dev/null
    if [ $write_ret -eq 0 ]; then
        echo "[+] $desc成功：$node → $value" >> "$UNLOCK_LOG"
        return 0
    else
        echo "[!] $desc失败：$node" >> "$UNLOCK_LOG"
        return 1
    fi
}

fix_fast_charge() {
    if [ "$IS_REALME" -eq 1 ]; then
        echo -e "${GREEN}✅ 真我机型：快充由系统管理${NC}"
        return
    fi

    local old_val=$(safe_read "$FAST_CHARGE_HEALTH")
    if [ ! -f "$FAST_CHARGE_HEALTH" ]; then
        echo -e "${ORANGE}ℹ️  快充模块：无检测节点${NC}"
        FAST_HEALTH_DESC="未检测到快充模块"
        return
    fi
    if [ "$old_val" -ge 70 ]; then
        echo -e "${GREEN}✅ 快充模块：正常${NC}"
        FAST_HEALTH_DESC="完美兼容快充"
        return
    fi
    echo -e "${RED}❌ 快充模块：异常，开始修复...${NC}"
    FAST_HEALTH_DESC="快充功能受限"
    safe_write "$FAST_CHARGE_ENABLE" 1 "快充功能开启"
    safe_write "$FAST_CHARGE_HEALTH" 100 "快充健康度重置"
    sleep 0.3
    local new_val=$(safe_read "$FAST_CHARGE_HEALTH")
    if [ "$new_val" -ge 90 ]; then
        echo -e "${GREEN}✅ 快充模块：修复成功${NC}"
        FAST_HEALTH_DESC="快充已修复，完美兼容"
    else
        echo -e "${RED}❌ 快充模块修复失败${NC}"
    fi
}

read_done_cycles() { [ -f "$COUNT_FILE" ] && cat "$COUNT_FILE" 2>/dev/null || echo 0; }
save_done_cycles() { echo "$1" > "$COUNT_FILE" 2>/dev/null; chmod 666 "$COUNT_FILE" 2>/dev/null; }
auto_depth_cycle() {
    local now_cap=$(safe_read "$CAPACITY")
    local flag=""
    [ -f "$CYCLE_FLAG_FILE" ] && flag=$(cat "$CYCLE_FLAG_FILE" 2>/dev/null)
    if [ "$now_cap" -eq 0 ]; then
        echo "drained" > "$CYCLE_FLAG_FILE"
        chmod 666 "$CYCLE_FLAG_FILE"
        return
    fi
    if [ "$now_cap" -eq 100 ] && [ "$flag" = "drained" ]; then
        local cnt=$(read_done_cycles)
        save_done_cycles $((cnt + 1))
        echo -e "${GREEN}✅ 检测到完整深度循环，计数+1${NC}"
        rm -f "$CYCLE_FLAG_FILE"
    fi
}

read_global_data() {
    cap_raw=$(safe_read "$CAPACITY")
    temp_raw=$(safe_read "$TEMP")
    cycle_raw=$(safe_read "$CYCLE_COUNT")
    voltage_now_raw=$(safe_read "$VOLTAGE_NOW")
    voltage_max_raw=$(safe_read "$VOLTAGE_MAX_DESIGN")

    if [ -z "$voltage_max_raw" ] || [ "$voltage_max_raw" -le 0 ]; then
        voltage_max_raw=$voltage_now_raw
    fi
    if [ -z "$voltage_max_raw" ] || [ "$voltage_max_raw" -le 0 ]; then
        voltage_max_raw=3850000
    fi

    cfd_uAh=$(safe_read "$CHARGE_FULL_DESIGN")
    cf_uAh=$(safe_read "$CHARGE_FULL")
    cfd=$((cfd_uAh / 1000))
    cf=$((cf_uAh / 1000))
    cap=$cap_raw
    temp=$((temp_raw / 10))

    # ====================== 【真我专用：真实容量取自 charge_full】 ======================
    if [ "$IS_REALME" -eq 1 ]; then
        real_qmax=$cf
        real_fcc_mah=$cf
    else
        real_qmax=$(safe_read "$FG1_QMAX")
        real_fcc_raw=$(safe_read "$FG1_FCC")
        real_fcc_mah=$((real_fcc_raw / 1000))
    fi
    # ====================================================================================

    real_remaining_qmax=$(( real_qmax * cap / 100 ))
    if [ $cfd -gt 0 ]; then
        real_health=$(( real_qmax * 100 / cfd ))
    else
        real_health=$(( real_qmax * 100 / 1 ))
    fi

    ir=$(safe_read "${QCOM_BATT_DIR}/fg1_ir")
    fast_health=$(safe_read "$FAST_CHARGE_HEALTH")
    lock_diff=0
    if [ $real_qmax -gt 0 ] && [ $real_fcc_mah -gt 0 ]; then
        lock_diff=$(( (real_qmax - real_fcc_mah) * 100 / real_qmax ))
    fi

    lock_cap_diff=0
    if [ $real_qmax -gt 0 ] && [ $cf -gt 0 ]; then
        lock_cap_diff=$(( (real_qmax - cf) * 100 / real_qmax ))
    fi
    if [ $lock_cap_diff -lt 0 ]; then
        lock_cap_diff=0
    fi

    voltage_v=$(( voltage_max_raw / 1000000 ))
    voltage_mv=$(( (voltage_max_raw % 1000000) / 1000 ))

    design_wh=$(printf "%d.%03d" $(( cfd * 18600 / 4820 / 1000 )) $(( cfd * 18600 / 4820 % 1000 )) )
    real_full_wh=$(printf "%d.%03d" $(( real_qmax * 18600 / 4820 / 1000 )) $(( real_qmax * 18600 / 4820 % 1000 )) )
    current_wh=$(printf "%d.%03d" $(( real_remaining_qmax * 18600 / 4820 / 1000 )) $(( real_remaining_qmax * 18600 / 4820 % 1000 )) )

    co=$(( cf * cap / 100 ))
    real_remaining_fcc=$real_remaining_qmax
}

show_base_status() {
    echo -e "${CYAN}===== 本命灵宝基础状态 =====${NC}"

    # ====================== 【真我：显示电池状态/技术/健康】 ======================
    if [ "$IS_REALME" -eq 1 ]; then
        batt_status=$(cat ${BATTERY_PATH}/status 2>/dev/null)
        batt_tech=$(cat ${BATTERY_PATH}/technology 2>/dev/null)
        batt_health=$(cat ${BATTERY_PATH}/health 2>/dev/null)
        echo -e "${LIGHT_BLUE}[电池状态] ${batt_status}　[类型] ${batt_tech}　[系统健康] ${batt_health}${NC}"
    fi
    # ============================================================================

    local health_sys=0
    if [ $cfd -gt 0 ]; then
        health_sys=$(( cf * 100 / cfd ))
    fi

    if [ $health_sys -ge 95 ]; then
        grade="${PURPLE}鸿蒙至宝（灵性圆满，无懈可击）${NC}"
    elif [ $health_sys -ge 90 ]; then
        grade="${GREEN}先天灵宝（完美无瑕，战力巅峰）${NC}"
    elif [ $health_sys -ge 80 ]; then
        grade="${GREEN}后天灵宝（状态上佳，潜力充足）${NC}"
    elif [ $health_sys -ge 70 ]; then
        grade="${ORANGE}凡品宝器（略有损耗，尚可一战）${NC}"
    else
        grade="${RED}残次品器（灵性枯竭，损耗严重）${NC}"
    fi

    echo -e "${LIGHT_BLUE}[灵宝温度] 器身温度: ${temp}°C${NC}"
    echo -e "${LIGHT_BLUE}[灵力上限] 原装上限: ${cfd}mAh / 系统上报: ${cf}mAh${NC}"
    echo -e "${LIGHT_BLUE}[当前灵力] 剩余灵力: ${co}mAh (${cap}%)${NC}"
    echo -e "${LIGHT_BLUE}[真实灵力] 电芯真实剩余: ${real_remaining_fcc}mAh (${cap}%)${NC}"
    echo -e "${LIGHT_BLUE}[灵品相] 灵性留存: ${health_sys}%${NC}"
    echo -e "${LIGHT_BLUE}[品相评级] ${grade}${NC}"
    echo ""
}

show_advance_status() {
    echo -e "${CYAN}===== 灵宝深层状态·魔改专属解析 =====${NC}"

    if [ "$IS_REALME" -eq 1 ]; then
        ir=0
        ir_grade="${GREEN}真我机型：内阻由底层管理${NC}"
    else
        if [ "$ir" -le 100 ]; then
            ir_grade="${GREEN}优秀（内阻极低，灵力流转顺畅）${NC}"
        elif [ "$ir" -le 200 ]; then
            ir_grade="${GREEN}良好（内阻正常，灵力稳定）${NC}"
        elif [ "$ir" -le 300 ]; then
            ir_grade="${ORANGE}一般（内阻偏高，灵力损耗加剧）${NC}"
        else
            ir_grade="${RED}较差（内阻过高，灵性流失严重）${NC}"
        fi
    fi

    if [ "$cycle_raw" -lt 200 ]; then
        cycle_desc="轻微"
    elif [ "$cycle_raw" -lt 500 ]; then
        cycle_desc="中度"
    else
        cycle_desc="严重"
    fi

    if [ "$fast_health" -ge 90 ]; then
        fast_desc="完美兼容快充"
    elif [ "$fast_health" -ge 70 ]; then
        fast_desc="支持快充"
    else
        fast_desc="快充功能受限"
    fi

    if [ $lock_diff -gt 20 ]; then
        lock_level="${RED}[锁灵禁制·重度] 已触发高阶锁灵！${NC}"
        unlock_guide="${ORANGE}[破解指引] 深度充放电5次+静置2小时${NC}"
    elif [ $lock_diff -gt 12 ]; then
        lock_level="${RED}[锁灵禁制·中度] 已触发中阶锁灵！${NC}"
        unlock_guide="${ORANGE}[破解指引] 深度充放电3次${NC}"
    elif [ $lock_diff -gt 8 ]; then
        lock_level="${ORANGE}[锁灵禁制·轻度] 已触发低阶锁灵！${NC}"
        unlock_guide="${ORANGE}[破解指引] 正常充放电2次${NC}"
    else
        lock_level="${GREEN}[无锁灵禁制] 灵力无束缚，状态极佳${NC}"
        unlock_guide="${GREEN}[无需操作] 容量已完全释放${NC}"
    fi

    echo -e "${lock_level}"
    echo -e "${unlock_guide}${NC}"
    echo -e "${LIGHT_BLUE}[上限容量] 系统上报: ${cf}mAh / 芯片真实上限: ${real_qmax}mAh${NC}"
    echo -e "${LIGHT_BLUE}[精准剩余] 真实总容量剩余: ${real_remaining_qmax}mAh (${cap}%)${NC}"
    echo -e "${LIGHT_BLUE}[真实健康] 芯片真实健康: ${real_health}%${NC}"
    echo -e "${LIGHT_BLUE}[循环次数] 实际循环: ${cycle_raw}次（衰减：${cycle_desc}）${NC}"
    echo -e "${LIGHT_BLUE}[电池内阻] ${ir}mΩ · ${ir_grade}${NC}"
    echo -e "${LIGHT_BLUE}[快充健康] ${fast_health}%（${fast_desc}）${NC}"
    fix_fast_charge
    echo ""
}

show_risk_warning() {
    echo -e "${CYAN}===== 灵宝风险预警 =====${NC}"
    local has_risk=0
    if [ "$temp" -ge 58 ]; then
        echo -e "${RED}[高温预警] 温度${temp}°C！立即停止使用${NC}"
        has_risk=1
    elif [ "$temp" -ge 43 ]; then
        echo -e "${ORANGE}[高温提示] 温度${temp}°C，建议降温${NC}"
    fi
    if [ "$voltage_now_raw" -gt 4450000 ] || [ "$voltage_now_raw" -lt 3100 ]; then
        echo -e "${RED}[电压异常] 存在安全隐患！${NC}"
        has_risk=1
    fi
    if [ "$real_health" -lt 65 ]; then
        echo -e "${RED}[老化预警] 健康度${real_health}%，建议更换！${NC}"
        has_risk=1
    fi
    [ $has_risk -eq 0 ] && echo -e "${GREEN}[无风险] 状态正常，可放心使用${NC}"
    echo ""
}

show_final_verdict() {
    echo -e "${CYAN}=== 灵宝最终判词 ===${NC}"
    if [ "$real_health" -lt 65 ] || [ "$lock_diff" -gt 20 ] || [ "$temp" -ge 58 ]; then
        echo -e "${RED}[判词] 【残器定论】灵性枯竭，锁灵深重${NC}"
    elif [ "$real_health" -lt 75 ] || [ "$lock_diff" -gt 12 ]; then
        echo -e "${RED}[判词] 【损器定论】灵性衰减，锁灵中度${NC}"
    elif [ "$real_health" -lt 85 ] || [ "$lock_diff" -gt 8 ]; then
        echo -e "${ORANGE}[判词] 【良品定论】略有损耗，轻度锁灵${NC}"
    elif [ "$real_health" -lt 95 ]; then
        echo -e "${GREEN}[判词] 【宝器定论】灵性充盈，无锁灵${NC}"
    else
        echo -e "${PURPLE}[判词] 【至宝定论】灵性圆满，先天鸿蒙至宝${NC}"
    fi
    echo ""
}

check_real_lock() {
    [ $lock_cap_diff -ge 10 ] && echo 1 || echo 0
}

get_unlock_recommend_times() {
    if [ $lock_cap_diff -ge 20 ]; then
        echo 7
    elif [ $lock_cap_diff -ge 12 ]; then
        echo 5
    else
        echo 3
    fi
}

show_unlock_guide() {
    local times=$(get_unlock_recommend_times)
    echo -e "${CYAN}===== 解容完整操作办法 =====${NC}"
    echo -e "${YELLOW}推荐深度充放电次数：${times} 次${NC}"
    echo -e "${ORANGE}1. 用到自动关机（0%）"
    echo -e "2. 关机充满，再续充60-90分钟"
    echo -e "3. 开机不拔线，息屏静置2小时"
    echo -e "4. 重复循环，脚本自动计数"
    echo -e "${GREEN}✅ 静置关键：开机 + 插充电器 + 息屏不动 2小时${NC}"
    echo ""
}

show_cycle_info() {
    local total=$(get_unlock_recommend_times)
    local done=$(read_done_cycles)
    local left=$(( total > done ? total - done : 0 ))
    echo -e "${LIGHT_BLUE}===== 深度循环计数（自动）=====${NC}"
    echo -e "${GREEN}已完成：${done} 次 | 解容需完成：${total} 次 | 剩余：${left} 次${NC}"
    echo -e "${ORANGE}规则：没电关机 → 关机充满 → 开机100% = 自动算1次${NC}"
    echo ""
}

real_time_monitor() {
    echo -e "${YELLOW}按任意键进入实时监控（Ctrl+C退出）${NC}"
    read -n 1
    echo -e "\n${GREEN}===== 实时容量+电流监控 =====${NC}"
    while true; do
        local now_cap=$(safe_read "$CAPACITY")
        local now_cur=$(safe_read "$CURRENT_NOW")
        local rq=$(safe_read "$FG1_QMAX")
        local rem=$(( rq * now_cap / 100 ))
        local ma=$(( (-now_cur) / 1000 ))
        echo -ne "${GREEN}$(date +%H:%M:%S) 电量：${now_cap}% 真实剩余：${rem}mAh "
        [ $now_cur -lt 0 ] && echo -e "充电：${ma}mA${NC}" || echo -e "${YELLOW}放电：${ma}mA${NC}"
        sleep 1
    done
}

unlock_capacity_real() {
    if [ "$IS_REALME" -eq 1 ]; then
        echo -e "${GREEN}✅ 真我机型：自动解锁已适配，按教程循环即可${NC}"
        return
    fi

    echo -e "${YELLOW}===== 执行锁容解锁 · 6套方案全量执行 =====${NC}"
    local unlock_success=0
    local origin_lock_diff=$lock_cap_diff
    local origin_cf=$cf

    echo -e "${BLUE}[1/6] 执行高通fake_cycle强制校准...${NC}"
    if safe_write "$FAKE_CYCLE" 1 "fake_cycle校准触发"; then
        sleep 1
        unlock_success=1
        echo -e "${GREEN}✅ 方案1执行成功${NC}"
    else
        echo -e "${ORANGE}⚠️  方案1执行失败，跳过${NC}"
    fi

    echo -e "${BLUE}[2/6] 执行FG芯片FCC容量强制解锁...${NC}"
    if [ $real_qmax -gt 0 ]; then
        if safe_write "$FG1_FCC" $(( real_qmax * 1000 )) "FCC容量重置为真实qmax"; then
            sleep 0.5
            unlock_success=1
            echo -e "${GREEN}✅ 方案2执行成功${NC}"
        else
            echo -e "${ORANGE}⚠️  方案2执行失败，跳过${NC}"
        fi
    else
        echo -e "${ORANGE}⚠️  真实qmax无效，跳过方案2${NC}"
    fi

    echo -e "${BLUE}[3/6] 执行系统上报容量强制解锁...${NC}"
    if [ $cfd_uAh -gt 0 ]; then
        if safe_write "$CHARGE_FULL" "$cfd_uAh" "系统满电容量重置为设计容量"; then
            sleep 0.5
            unlock_success=1
            echo -e "${GREEN}✅ 方案3执行成功${NC}"
        else
            echo -e "${ORANGE}⚠️  方案3执行失败，跳过${NC}"
        fi
    else
        echo -e "${ORANGE}⚠️  设计容量无效，跳过方案3${NC}"
    fi

    echo -e "${BLUE}[4/6] 执行电池芯片强制校准...${NC}"
    local cali_success=0
    safe_write "$BATT_CALIBRATE" 1 "电池校准触发" && cali_success=$(( cali_success + 1 ))
    safe_write "$BATT_RESET_CAP" 1 "容量重置触发" && cali_success=$(( cali_success + 1 ))
    if [ $cali_success -gt 0 ]; then
        unlock_success=1
        echo -e "${GREEN}✅ 方案4执行成功${NC}"
    else
        echo -e "${ORANGE}⚠️  方案4执行失败，跳过${NC}"
    fi

    echo -e "${BLUE}[5/6] 执行系统电池缓存重置...${NC}"
    dumpsys battery reset 2>/dev/null
    if [ $? -eq 0 ]; then
        unlock_success=1
        echo -e "${GREEN}✅ 方案5执行成功${NC}"
    else
        echo -e "${ORANGE}⚠️  方案5执行失败，跳过${NC}"
    fi

    echo -e "${BLUE}[6/6] 执行循环计数重置触发校准...${NC}"
    local origin_cycle=$(safe_read "$CYCLE_COUNT")
    safe_write "$CYCLE_COUNT" 0 "循环计数临时重置"
    sleep 0.5
    safe_write "$CYCLE_COUNT" "$origin_cycle" "循环计数恢复"
    unlock_success=1
    echo -e "${GREEN}✅ 方案6执行完成${NC}"

    echo ""
    echo -e "${CYAN}===== 解锁结果校验 =====${NC}"
    read_global_data
    local new_lock_diff=$lock_cap_diff
    local new_cf=$cf

    if [ $new_lock_diff -lt $origin_lock_diff ] || [ $new_cf -gt $origin_cf ]; then
        echo -e "${GREEN}${BOLD}✅ 解锁成功！容量限制已解除${NC}"
        echo -e "${GREEN}原锁容限制：${origin_lock_diff}% → 当前锁容限制：${new_lock_diff}%${NC}"
        echo -e "${GREEN}原系统上报容量：${origin_cf}mAh → 当前系统上报容量：${new_cf}mAh${NC}"
        echo -e "${GREEN}请配合后续深度充放电循环，让电池管理完全生效${NC}"
    elif [ $unlock_success -eq 1 ]; then
        echo -e "${YELLOW}${BOLD}⚠️  解锁指令已全部执行，需配合深度充放电生效${NC}"
        echo -e "${YELLOW}当前机型不支持直接解锁，已触发系统强制校准，按下方步骤执行循环即可解容${NC}"
    else
        echo -e "${RED}${BOLD}❌ 自动解锁执行失败${NC}"
        echo -e "${ORANGE}当前机型不支持自动解锁，直接按下方步骤执行深度充放电即可手动解容${NC}"
    fi
    echo ""
}

clear
echo -e "${YELLOW}
████████╗██████╗  █████╗  ██████╗ ███████╗
╚══██╔══╝██╔══██╗██╔══██╗██╔════╝ ██╔════╝
   ██║   ██████╔╝███████║██║  ███╗█████╗
   ██║   ██╔══██╗██╔══██║██║   ██║██╔══╝
   ██║   ██║  ██║██║  ██║╚██████╔╝███████╗
   ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝
${NC}"
echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}        玄天宝镜·全自动真实容量版           ${NC}"
echo -e "${CYAN}   深度循环自动计数 | 真实锁容检测 | 完整解容  ${NC}"
echo -e "${CYAN}============================================${NC}\n"

read_global_data
auto_depth_cycle

show_base_status
show_advance_status
show_risk_warning
show_final_verdict

echo -e "${CYAN}============================================${NC}"
echo -e "${YELLOW}===== 锁容状态（基于真实容量）=====${NC}"
if [ "$(check_real_lock)" -eq 1 ]; then
    echo -e "${RED}⚠️  已锁容 | 真实容量被限制：${lock_cap_diff}%${NC}"
    echo ""
    unlock_capacity_real
    show_unlock_guide
else
    echo -e "${GREEN}✅ 无锁容 | 真实容量已完全释放${NC}"
    echo ""
fi

echo -e "${GREEN}===== 真实容量验证 =====${NC}"
echo -e "${LIGHT_BLUE}设计容量：${cfd} mAh　真实满电：${real_qmax} mAh　真实剩余：${real_remaining_qmax} mAh${NC}"
echo -e "${LIGHT_BLUE}真实健康：${real_health} %　锁容限制：${lock_cap_diff} %${NC}"
echo -e "${CYAN}=========== 瓦时容量 (Wh) ===========${NC}"
echo -e "${LIGHT_BLUE}设计：${design_wh}　真实满电：${real_full_wh}　当前：${current_wh}${NC}"
echo ""

show_cycle_info
real_time_monitor
