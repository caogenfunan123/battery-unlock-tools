/*
 * k60_fcc_unlock.c - KernelSU module to unlock 6500mAh battery capacity
 * on Redmi K60 (mondrian, qti_battery_charger).
 *
 * Strategy (Route B): hook battery_chg_write() with a kprobe. When the
 * vendor driver writes a FAKE_SOH property to the XM firmware, rewrite the
 * property_id to FG1_FCC and value to 6500000 (uAh). The firmware then
 * applies the capacity directly instead of a fake SOH.
 *
 * Trigger: echo 6500000 > /sys/class/qcom-battery/fake_soh
 *
 * Requires only GKI-stable symbols (register_kprobe/unregister_kprobe),
 * so it can be built against the stock android12-5.10 GKI tree.
 *
 * Layout of battery_charger_req_msg (u32 words, little-endian):
 *   +0  pmic_glink_hdr {owner, type, opcode}
 *   +12 battery_id
 *   +16 property_id
 *   +20 value
 *
 * arm64 ABI: x0=bcdev, x1=data(req_msg), x2=len
 */
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/kprobes.h>
#include <linux/ptrace.h>
#include <linux/uaccess.h>

#define XM_PROP_FAKE_SOH   93
#define XM_PROP_FG1_FCC    120

#define REQ_MSG_PROP_ID_OFF  16
#define REQ_MSG_VALUE_OFF    20

static unsigned int target_fcc = 6500000;
module_param(target_fcc, uint, 0644);
MODULE_PARM_DESC(target_fcc, "Capacity to program into FG1_FCC in uAh");

static struct kprobe kp;

static int k60_pre_handler(struct kprobe *p, struct pt_regs *regs)
{
	/*
	 * battery_chg_write(bcdev, data, len): data is the KERNEL stack
	 * address of a battery_charger_req_msg built by write_property_id().
	 * regs[1] (x1) = data. Must dereference directly - get_user would
	 * reject kernel addresses. This runs synchronously before the real
	 * function body, so mutating the caller's stack frame is safe.
	 */
	u32 *msg = (u32 __user *)regs->regs[1];

	if (!msg)
		return 0;

	/* only touch FAKE_SOH write requests (offset 16 = word 4) */
	if (msg[REQ_MSG_PROP_ID_OFF / 4] != XM_PROP_FAKE_SOH)
		return 0;

	pr_info("k60_unlock: rewrite FAKE_SOH -> FG1_FCC value %u -> %u\n",
		msg[REQ_MSG_VALUE_OFF / 4], target_fcc);

	msg[REQ_MSG_PROP_ID_OFF / 4] = XM_PROP_FG1_FCC;
	msg[REQ_MSG_VALUE_OFF / 4] = target_fcc;
	return 0;
}

static int __init k60_unlock_init(void)
{
	kp.symbol_name = "battery_chg_write";
	kp.pre_handler = k60_pre_handler;

	if (register_kprobe(&kp)) {
		pr_err("k60_unlock: register_kprobe(battery_chg_write) failed\n");
		return -EINVAL;
	}
	pr_info("k60_unlock: kprobe on battery_chg_write registered, "
		"target_fcc=%u uAh\n", target_fcc);
	return 0;
}

static void __exit k60_unlock_exit(void)
{
	unregister_kprobe(&kp);
	pr_info("k60_unlock: kprobe removed\n");
}

module_init(k60_unlock_init);
module_exit(k60_unlock_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("k60-battery-unlock");
MODULE_DESCRIPTION("K60 6500mAh capacity unlock via kprobe on battery_chg_write");
