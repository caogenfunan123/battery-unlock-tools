#!/system/bin/sh
#
# boot-completed.sh - KernelSU official hook, runs in SERVICE mode AFTER
# the Android system has fully booted (ACTION_BOOT_COMPLETED).
#
#   A. Load the voltage probe ko (k60_volt_probe.ko) - optional, may fail (CFI)
#   B. Lock fake_cycle to 1 (cycle lock unlock)
#   C. Ensure the self-healing guard daemon is running (fallback path).
#   D. Real-SOC daemon: display true physical capacity (rm/qmax*100).
MODDIR=${0%/*}
GUARD_LOG=$MODDIR/guard.log
QB=/sys/class/qcom-battery
VOLT_KO=$MODDIR/kernel/k60_volt_probe.ko

i=0
while [ ! -e $QB/fg1_fcc ] && [ "$i" -lt 30 ]; do
    i=$((i+1))
    sleep 1
done

# ---- A. 4.5V voltage probe (best effort) ----
VOLT_UV=4500000
if [ -f "$VOLT_KO" ]; then
    if lsmod 2>/dev/null | grep -q k60_volt_probe; then
        echo "$(date '+%F %T') volt probe already loaded" >> "$GUARD_LOG"
    else
        if insmod "$VOLT_KO" target_volt=$VOLT_UV 2>/dev/null; then
            echo "$(date '+%F %T') volt probe loaded target=$VOLT_UV uV" >> "$GUARD_LOG"
        else
            echo "$(date '+%F %T') FAILED to insmod volt probe: $(insmod "$VOLT_KO" 2>&1)" >> "$GUARD_LOG"
        fi
    fi
else
    echo "$(date '+%F %T') volt probe ko missing: $VOLT_KO" >> "$GUARD_LOG"
fi

# ---- B. lock displayed cycle count to 0 ----
if [ -e "$QB/fake_cycle" ]; then
    echo 1 > "$QB/fake_cycle" 2>/dev/null
fi

# ---- C. fallback guard daemon ----
if [ -f "$MODDIR/scripts/k60_guard.sh" ]; then
    sh "$MODDIR/scripts/k60_guard.sh" start
fi

# ---- D. real SOC daemon (physical capacity display, revert: kill the proc && echo 1 > fake_soc) ----
[ -f "$MODDIR/scripts/real_soc_daemon.sh" ] && nohup /system/bin/sh "$MODDIR/scripts/real_soc_daemon.sh" >/dev/null 2>&1 &

[ -f "$MODDIR/scripts/charge_learn.sh" ] && nohup /system/bin/sh "$MODDIR/scripts/charge_learn.sh" >/dev/null 2>&1 &
[ -f "/data/local/tmp/charge_watch.sh" ] && nohup /system/bin/sh /data/local/tmp/charge_watch.sh >/dev/null 2>&1 &
[ -f /data/local/tmp/httpd_start.sh ] && /system/bin/sh /data/local/tmp/httpd_start.sh
exit 0