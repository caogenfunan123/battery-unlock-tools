/*
 * k60_fcc_probe.c - test which firmware property the XM firmware accepts
 * as a write target. Reuses the proven FAKE_SOH write path (a fake_soh
 * sysfs write reaches the firmware), rewriting the property_id to a
 * candidate and watching which one moves fg1_fcc / fg1_soh.
 *
 * Load with the desired target prop as a module parameter, then do:
 *   echo 1 > /sys/class/qcom-battery/fake_soh
 * and observe the battery values.
 *
 * Usage:
 *   insmod k60_fcc_probe.ko target_prop=121   # try FG1_SOH
 *   insmod k60_fcc_probe.ko target_prop=122   # try FG1_FCC_SOH
 *   insmod k60_fcc_probe.ko target_prop=118   # try FG1_QMAX
 *   insmod k60_fcc_probe.ko target_prop=119   # try FG1_RM
 *
 * target_prop values (verified enum):
 *   118 FG1_QMAX, 119 FG1_RM, 120 FG1_FCC, 121 FG1_SOH, 122 FG1_FCC_SOH
 */
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/kprobes.h>
#include <linux/ptrace.h>

#define XM_PROP_FAKE_SOH 93
#define REQ_MSG_OPCODE_OFF 8
#define REQ_MSG_PROP_ID_OFF 16
#define REQ_MSG_VALUE_OFF   20
#define REQ_MSG_MIN_LEN     24
#define BC_XM_STATUS_SET    0x51
#define BC_XM_STATUS_GET    0x50

static unsigned int target_prop = 121;
module_param(target_prop, uint, 0644);
MODULE_PARM_DESC(target_prop, "property id to rewrite fake_soh into (118-122)");

static unsigned int target_value = 100;
module_param(target_value, uint, 0644);
MODULE_PARM_DESC(target_value, "value to write to the target property");

static unsigned int match_opcode = BC_XM_STATUS_SET;
module_param(match_opcode, uint, 0644);
MODULE_PARM_DESC(match_opcode, "only rewrite messages with this opcode (default 0x51=XM SET)");

static unsigned long hit_count;
module_param(hit_count, ulong, 0644);

static struct kprobe kp;

static int k60_pre_handler(struct kprobe *p, struct pt_regs *regs)
{
	u32 *msg = (u32 *)regs->regs[1];
	unsigned long len = regs->regs[2];
	u32 opcode;

	if (!msg || len < REQ_MSG_MIN_LEN)
		return 0;

	opcode = msg[REQ_MSG_OPCODE_OFF / 4];
	if (opcode != match_opcode)
		return 0;			/* GET (0x50) must stay untouched so reads are truthful */
	if (msg[REQ_MSG_PROP_ID_OFF / 4] != XM_PROP_FAKE_SOH)
		return 0;

	hit_count++;

	pr_info("k60_probe: 0x%x rewrite fake_soh -> prop=%u val=%u (was %u)\n",
		opcode, target_prop, target_value, msg[REQ_MSG_VALUE_OFF / 4]);

	msg[REQ_MSG_PROP_ID_OFF / 4] = target_prop;
	msg[REQ_MSG_VALUE_OFF / 4] = target_value;
	return 0;
}

static int __init k60_probe_init(void)
{
	kp.symbol_name = "battery_chg_write";
	kp.pre_handler = k60_pre_handler;

	if (register_kprobe(&kp)) {
		pr_err("k60_probe: register_kprobe failed\n");
		return -EINVAL;
	}
	pr_info("k60_probe: registered, target_prop=%u target_value=%u\n",
		target_prop, target_value);
	return 0;
}

static void __exit k60_probe_exit(void)
{
	unregister_kprobe(&kp);
}

module_init(k60_probe_init);
module_exit(k60_probe_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("k60-battery-unlock");
MODULE_DESCRIPTION("Probe which XM firmware property accepts writes");
