/*
 * k60_idscan.c - dump all battery_charger_req_msg leaving the driver,
 * revealing the REAL XM firmware property-id table in use on this device.
 *
 * Why: the xm_property_id enum differs across kernels (CONFIG toggles shift
 * ids), so we cannot trust source-code numbering. This probe dumps every
 * message the driver sends to the firmware (opcode + property + value),
 * including periodic writes from HAL/services - we learn the true ids of
 * SMART_BATT / FAKE_SOH / FAKE_CYCLE / START_LEARN / SET_REFERANCE_POWER etc.
 *
 * Usage: insmod k60_idscan.ko          # dump-only, zero side effects
 *   config:  max_lines  (default 200)  # stop logging after N lines
 *            rate_ms    (default 100)  # min ms between log lines (debounce)
 * Toggle off: echo 0 > /sys/module/k60_idscan/parameters/enable
 *
 * Result in dmesg:  k60_scan: w opcode=0x51 prop=93 val=100 len=24
 *                   k60_scan: g opcode=0x50 prop=120 val=0 len=24
 * w = write(0x51), g = read(0x50), also 0x31 batt channel.
 */
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/kprobes.h>
#include <linux/ptrace.h>
#include <linux/timekeeping.h>

#define REQ_HDR_OWNER_OFF  0
#define REQ_OPCODE_OFF     8
#define REQ_PROP_OFF       16
#define REQ_VALUE_OFF      20

static unsigned int enable = 1;
module_param(enable, uint, 0644);
static unsigned int max_lines = 200;
module_param(max_lines, uint, 0644);
static unsigned int rate_ms = 100;
module_param(rate_ms, uint, 0644);

static struct kprobe kp;
static unsigned long count;
static unsigned long last_jiffies;

static int scan_pre(struct kprobe *p, struct pt_regs *regs)
{
	u32 *msg;
	unsigned long now;
	unsigned int opcode, prop, val;

	if (!enable)
		return 0;
	if (count >= max_lines)
		return 0;

	now = jiffies;
	if (last_jiffies && time_before(now, last_jiffies + msecs_to_jiffies(rate_ms)))
		return 0;
	last_jiffies = now;

	msg = (u32 *)regs->regs[1];
	if (!msg)
		return 0;

	opcode = msg[REQ_OPCODE_OFF / 4];
	prop   = msg[REQ_PROP_OFF / 4];
	val    = msg[REQ_VALUE_OFF / 4];

	pr_info("k60_scan: opcode=0x%x prop=%u val=%u (msg=%px)
",
		opcode, prop, val, (void *)msg);
	count++;
	return 0;
}

static int __init k60_scan_init(void)
{
	kp.symbol_name = "battery_chg_write";
	kp.pre_handler = scan_pre;
	if (register_kprobe(&kp)) {
		pr_err("k60_scan: register_kprobe(battery_chg_write) failed\n");
		return -EINVAL;
	}
	pr_info("k60_scan: probing battery_chg_write, max_lines=%u rate_ms=%u\n",
		max_lines, rate_ms);
	return 0;
}

static void __exit k60_scan_exit(void)
{
	unregister_kprobe(&kp);
	pr_info("k60_scan: unloaded, lines=%lu\n", count);
}

module_init(k60_scan_init);
module_exit(k60_scan_exit);

MODULE_LICENSE("GPL");
