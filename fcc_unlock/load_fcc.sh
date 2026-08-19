#!/system/bin/sh
# load_fcc.sh - read addresses from /proc/kallsyms, pass into module
set -x
echo 0 > /proc/sys/kernel/kptr_restrict 2>/dev/null

CHG=$(grep " battery_chg_write$" /proc/kallsyms | head -1 | awk '{print $1}')
PMAP=$(grep " battery_prop_map$" /proc/kallsyms | head -1 | awk '{print $1}')
PSYGET=$(grep " power_supply_get_by_name$" /proc/kallsyms | head -1 | awk '{print $1}')

echo "chg_write=$CHG prop_map=$PMAP psy_get=$PSYGET"

dmesg -c > /dev/null 2>&1
insmod /data/local/tmp/fcc_unlock.ko chg_write=0x$CHG prop_map=0x$PMAP psy_get=0x$PSYGET
echo "insmod exit=$?"
dmesg | tail -10
cat /sys/class/qcom-battery/fg1_fcc