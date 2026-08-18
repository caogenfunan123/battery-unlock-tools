/*
 * k60_volt_probe.c - lift the reported max battery voltage to 4.5V on
 * Redmi K60 (mondrian, qti_battery_charger).
 *
 * The firmware reports the cell's max voltage through two read-only
 * nodes:
 *   /sys/class/power_supply/battery/voltage_max  (BATT_VOLT_MAX, prop 8)
 *   /sys/class/qcom-battery/fg1_vol_max          (XM FG1_VOL_MAX, prop 126)
 *
 * Both come from the PMIC firmware via pmic_glink GET responses. The
 * values are read-only on the sysfs side, so to present 4.5V we hook the
 * response path: handle_message() copies the firmware response into
 * pst->prop[], which battery_psy_get_prop() then serves to userspace.
 * Rewriting resp_msg->value here makes every subsequent read show the
 * target voltage.
 *
 * arm64 ABI: handle_message(struct battery_chg_dev *bcdev, void *data,
 *             size_t len) => x0=bcdev, x1=data, x2=len.
 * battery_charger_resp_msg layout (u32 words):
 *   +0  pmic_glink_hdr {owner,type,opcode}
 *   +12 property_id
 *   +16 value
 *   +20 ret_code
 *
 * Module params (all 0644, runtime-changeable):
 *   target_volt   : voltage in uV to report (default 4500000 = 4.5V)
 *   volt_batt_prop: BATTERY-channel property to rewrite (default 8)
 *   volt_xm_prop  : XM-channel property to rewrite (default 126)
 *   match_get     : 1 = also rewrite GET responses (default 1)
 *   log_hits      : 1 = log each rewrite (default 0)
 */
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/kprobes.h>
#include <linux/ptrace.h>

#define RESP_MSG_OPCODE_OFF  8
#define RESP_MSG_PROP_ID_OFF 12
#define RESP_MSG_VALUE_OFF   16
#define RESP_MSG_MIN_LEN     24

#define BC_BATTERY_STATUS_GET 0x30
#define BC_XM_STATUS_GET      0x50

static unsigned int target_volt = 4500000;
module_param(target_volt, uint, 0644);
MODULE_PARM_DESC(target_volt, "voltage in uV to report (default 4500000 = 4.5V)");

static unsigned int volt_batt_prop = 8;
module_param(volt_batt_prop, uint, 0644);
MODULE_PARM_DESC(volt_batt_prop, "BATTERY channel prop id (default 8=BATT_VOLT_MAX)");

static unsigned int volt_xm_prop = 126;
module_param(volt_xm_prop, uint, 0644);
MODULE_PARM_DESC(volt_xm_prop, "XM channel prop id (default 126=FG1_VOL_MAX)");

static unsigned int log_hits;
module_param(log_hits, uint, 0644);

static unsigned long hit_count;
module_param(hit_count, ulong, 0644);

static struct kprobe kp;

static int k60_volt_pre_handler(struct kprobe *p, struct pt_regs *regs)
{
	u32 *msg = (u32 *)regs->regs[1];
	unsigned long len = regs->regs[2];
	u32 opcode, prop;

	if (!msg || len < RESP_MSG_MIN_LEN)
		return 0;

	opcode = msg[RESP_MSG_OPCODE_OFF / 4];
	prop = msg[RESP_MSG_PROP_ID_OFF / 4];

	if (opcode == BC_BATTERY_STATUS_GET && prop == volt_batt_prop) {
		msg[RESP_MSG_VALUE_OFF / 4] = target_volt;
		hit_count++;
		if (log_hits)
			pr_info("k60_volt: BATT prop %u -> %u uV (hits=%lu)\n",
				prop, target_volt, hit_count);
	} else if (opcode == BC_XM_STATUS_GET && prop == volt_xm_prop) {
		msg[RESP_MSG_VALUE_OFF / 4] = target_volt;
		hit_count++;
		if (log_hits)
			pr_info("k60_volt: XM prop %u -> %u uV (hits=%lu)\n",
				prop, target_volt, hit_count);
	}

	return 0;
}

static int __init k60_volt_init(void)
{
	kp.symbol_name = "handle_message";
	kp.pre_handler = k60_volt_pre_handler;

	if (register_kprobe(&kp)) {
		pr_err("k60_volt: register_kprobe(handle_message) failed\n");
		return -EINVAL;
	}
	pr_info("k60_volt: registered, target=%u uV batt_prop=%u xm_prop=%u\n",
		target_volt, volt_batt_prop, volt_xm_prop);
	return 0;
}

static void __exit k60_volt_exit(void)
{
	unregister_kprobe(&kp);
	pr_info("k60_volt: unregistered, total hits=%lu\n", hit_count);
}

module_init(k60_volt_init);
module_exit(k60_volt_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("k60-battery-unlock");
MODULE_DESCRIPTION("Report K60 max battery voltage as 4.5V via handle_message kprobe");
