#!/system/bin/sh
# charge_learn.sh v3.2 - aggressive fake_cycle=1 relock (60s) + learn on charge
LOG=/data/local/tmp/charge_learn.log
BAT=/sys/class/power_supply/battery/status
QB=/sys/class/qcom-battery
: > $LOG
echo "=== $(date '+%F %T') charge_learn v3.2 start (pid $$) ===" >> $LOG

i=0
while [ ! -e $QB/fake_cycle ] && [ $i -lt 60 ]; do i=$((i+1)); sleep 1; done
last=$(cat $BAT 2>/dev/null)
echo "initial status: $last" >> $LOG

lock_cycle() {
  cur=$(cat $QB/fake_cycle 2>/dev/null)
  if [ "$cur" != 1 ]; then
    chmod 777 $QB/fake_cycle 2>/dev/null
    echo 1 > $QB/fake_cycle 2>/dev/null
    chmod 644 $QB/fake_cycle 2>/dev/null
    echo "$(date '+%F %T') fake_cycle was $cur -> 1, reads: $(cat $QB/fake_cycle 2>/dev/null)" >> $LOG
  fi
  # also keep SOH locked at 100 while charging
  s=$(cat $QB/fg1_soh 2>/dev/null)
  if [ "$s" != 100 ]; then echo 100 > $QB/fake_soh 2>/dev/null; fi
}

lock_cycle
t=0
while true; do
  now=$(cat $BAT 2>/dev/null)
  if [ "$now" = "Charging" ] && [ "$last" != "Charging" ]; then
    lock_cycle
    echo 1 > $QB/start_learn 2>/dev/null
    echo "$(date '+%F %T') start_learn=1, reads: $(cat $QB/start_learn 2>/dev/null)" >> $LOG
    sleep 3
  fi
  last=$now
  t=$((t+20))
  # relock every 60s to beat firmware cycle-settlement overwrites
  if [ $((t % 60)) -eq 0 ]; then lock_cycle; fi
  sleep 20
done