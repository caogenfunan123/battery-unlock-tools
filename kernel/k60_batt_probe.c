/*
 * k60_batt_probe.c - intercept the BATTERY glink channel (opcode 0x31)
 * and rewrite an outgoing property write into BATT_CHG_FULL (prop 18).
 *
 * The stock driver's battery_psy_set_prop() rejects POWER_SUPPLY_PROP_CHARGE_FULL
 * with -EINVAL, so prop 18 (BATT_CHG_FULL) is NEVER written by the system.
 * This probe rides an existing system write on the 0x31 channel and rewrites
 * the message to prop 18 = target_value (default 6500000), then the firmware's
 * ret_code for that prop is captured via dmesg:
 *   "Error in response for opcode 0x31 prop_id 18, rc=X"
 *
 * Trigger sources (all go through write_property_id(BATTERY) -> opcode 0x31):
 *   echo 6500000 > /sys/class/power_supply/battery/constant_charge_current
 *   echo 6500000 > /sys/class/qcom-battery/restrict_cur
 *   echo 0 > /sys/class/power_supply/battery/charge_control_limit
 *
 * Module params (all 0644, changeable at runtime):
 *   match_opcode : only rewrite messages with this opcode (default 0x31)
 *   target_prop  : property id to write (default 18 = BATT_CHG_FULL)
 *   target_value : value to write (default 6500000 uAh)
 *   rewrite      : 1 = rewrite the message, 0 = log-only (default 1)
 */
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/kprobes.h>
#include <linux/ptrace.h>

#define BC_BATTERY_STATUS_SET 0x31
#define REQ_MSG_OPCODE_OFF    8    /* pmic_glink_hdr.opcode */
#define REQ_MSG_PROP_ID_OFF   16
#define REQ_MSG_VALUE_OFF     20
#define REQ_MSG_MIN_LEN       24   /* hdr + battery_id + property_id + value */

static unsigned int match_opcode = BC_BATTERY_STATUS_SET;
static unsigned int target_prop = 18;
static unsigned int target_value = 6500000;
static unsigned int rewrite = 1;
static unsigned long hit_count;

module_param(match_opcode, uint, 0644);
MODULE_PARM_DESC(match_opcode, "only rewrite messages with this opcode (default 0x31)");
module_param(target_prop, uint, 0644);
MODULE_PARM_DESC(target_prop, "property id to write (default 18=BATT_CHG_FULL)");
module_param(target_value, uint, 0644);
MODULE_PARM_DESC(target_value, "value to write (default 6500000 uAh)");
module_param(rewrite, uint, 0644);
MODULE_PARM_DESC(rewrite, "1=rewrite message, 0=log only");
module_param(hit_count, ulong, 0644);

static struct kprobe kp;

static int k60_pre_handler(struct kprobe *p, struct pt_regs *regs)
{
	u32 *msg = (u32 *)regs->regs[1];
	unsigned long len = regs->regs[2];
	u32 opcode, prop, val;

	if (!msg || len < REQ_MSG_MIN_LEN)
		return 0;

	opcode = msg[REQ_MSG_OPCODE_OFF / 4];
	if (opcode != match_opcode)
		return 0;

	prop = msg[REQ_MSG_PROP_ID_OFF / 4];
	val = msg[REQ_MSG_VALUE_OFF / 4];
	hit_count++;

	if (rewrite) {
		pr_info("k60_batt: 0x%x prop=%u val=%u -> rewrite prop=%u val=%u\n",
			opcode, prop, val, target_prop, target_value);
		msg[REQ_MSG_PROP_ID_OFF / 4] = target_prop;
		msg[REQ_MSG_VALUE_OFF / 4] = target_value;
	} else {
		pr_info("k60_batt: 0x%x prop=%u val=%u (log only, hits=%lu)\n",
			opcode, prop, val, hit_count);
	}
	return 0;
}

static int __init k60_batt_init(void)
{
	kp.symbol_name = "battery_chg_write";
	kp.pre_handler = k60_pre_handler;

	if (register_kprobe(&kp)) {
		pr_err("k60_batt: register_kprobe failed\n");
		return -EINVAL;
	}
	pr_info("k60_batt: registered opcode=0x%x target_prop=%u val=%u rewrite=%u\n",
		match_opcode, target_prop, target_value, rewrite);
	return 0;
}

static void __exit k60_batt_exit(void)
{
	unregister_kprobe(&kp);
	pr_info("k60_batt: unregistered, total hits=%lu\n", hit_count);
}

module_init(k60_batt_init);
module_exit(k60_batt_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("k60-battery-unlock");
MODULE_DESCRIPTION("Intercept BATTERY channel 0x31 writes and rewrite to BATT_CHG_FULL");
