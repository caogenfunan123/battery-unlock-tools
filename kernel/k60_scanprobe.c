/*
 * k60_scanprobe.c v2 - PASSIVE dump + ACTIVE whitelist scan
 *
 * v1 (idscan) was passive-only: it recorded real traffic and found the
 * firmware accepts writes to props 83/88/90/92/93/102/103/104/108/82.
 * v2 adds ACTIVE SCANNING: we call the original function directly via the
 * kprobe address and send a SET (opcode 0x51) for EVERY prop id 0..max_prop.
 * The firmware's acceptance verdict shows up as "Error in response ... rc=NNN"
 * in dmesg (validate_message). Props with NO error = accepted writable ids.
 *
 * Layout (verified against observed traffic):
 *   +0  hdr.owner    (owner=2 MSG_OWNER_BC)
 *   +8  hdr.opcode   (0x51 set / 0x50 get)
 *   +16 property_id  (u32)
 *   +20 battery_id   (u32) 0
 *   +24 value        (u32)
 *   total 28 bytes as seen in src driver struct.
 *
 * Usage:
 *   insmod k60_scanprobe.ko            # passive only (like v1)
 *   echo 160 > /sys/module/k60_scanprobe/parameters/max_prop   # scan range
 *   echo 1   > /sys/module/k60_scanprobe/parameters/scan       # START SCAN
 *   # watch: dmesg -w | grep k60_scan
 *   echo 0   > /sys/module/k60_scanprobe/parameters/scan       # stop
 *
 * Scan writes val=1 then val=0 back for each prop (safe toggle). Charging
 * should be off during scan (some props gate USB/vbus).
 */
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/kprobes.h>
#include <linux/ptrace.h>
#include <linux/delay.h>
#include <linux/workqueue.h>

#define MSG_OWNER_BC 2
#define OPCODE_SET   0x51
#define OPCODE_GET   0x50

struct scan_msg {
	u32 hdr_owner;    /* +0 */
	u32 pad1;         /* +4 */
	u32 hdr_opcode;   /* +8 */
	u32 pad2;         /* +12 */
	u32 property_id;  /* +16 */
	u32 battery_id;   /* +20 */
	u32 value;        /* +24 */
};

static struct kprobe kp;
static unsigned int enable = 1;
module_param(enable, uint, 0644);
static unsigned int max_prop = 160;
module_param(max_prop, uint, 0644);
static unsigned int scan = 0;
module_param(scan, uint, 0644);
static unsigned int scan_done = 0;
module_param(scan_done, uint, 0444);

static struct workqueue_struct *wq;
static struct work_struct scan_work;
static ulong fn_addr;

static int (*real_write)(void *msg, size_t len);

static int scan_pre(struct kprobe *p, struct pt_regs *regs)
{
	u32 *msg;
	unsigned int opcode, prop, val;

	if (!enable)
		return 0;
	msg = (u32 *)regs->regs[1];
	if (!msg)
		return 0;
	opcode = msg[8 / 4];
	prop   = msg[16 / 4];
	val    = msg[24 / 4];
	pr_info("k60_scan: opcode=0x%x prop=%u val=%u len=%lu\n",
		opcode, prop, val, (unsigned long)regs->regs[2]);
	return 0;
}

static void scan_fn(struct work_struct *w)
{
	struct scan_msg m;
	unsigned int i;

	if (!fn_addr)
		return;
	pr_info("k60_scan: SCAN START max_prop=%u\n", max_prop);
	for (i = 0; i <= max_prop; i++) {
		memset(&m, 0, sizeof(m));
		m.hdr_owner = MSG_OWNER_BC;
		m.hdr_opcode = OPCODE_SET;
		m.property_id = i;
		m.battery_id = 0;
		m.value = 1;
		real_write(&m, sizeof(m));
		usleep_range(15000, 25000);
		/* toggle back to 0 for pure idempotent props */
		m.value = 0;
		real_write(&m, sizeof(m));
		usleep_range(15000, 25000);
	}
	pr_info("k60_scan: SCAN DONE sent 2x(%u+1) props\n", max_prop);
	scan = 0;
	scan_done = 1;
}

static int scan_set(const char *val, const struct kernel_param *kp_)
{
	int r = param_set_uint(val, kp_);

	if (r == 0 && scan && !scan_done) {
		if (wq)
			queue_work(wq, &scan_work);
	}
	return r;
}

static struct kernel_param_ops scan_ops = {
	.set = scan_set,
	.get = param_get_uint,
};
module_param_cb(scan, &scan_ops, &scan, 0644);

static int __init k60_scan_init(void)
{
	kp.symbol_name = "battery_chg_write";
	kp.pre_handler = scan_pre;
	if (register_kprobe(&kp)) {
		pr_err("k60_scan: register_kprobe failed\n");
		return -EINVAL;
	}
	fn_addr = (ulong)kp.addr;
	real_write = (int (*)(void *, size_t))kp.addr;
	wq = alloc_workqueue("k60_scanwq", WQ_UNBOUND, 0);
	INIT_WORK(&scan_work, scan_fn);
	pr_info("k60_scan: v2 loaded addr=%px scan=0 max_prop=%u\n",
		(void *)fn_addr, max_prop);
	return 0;
}

static void __exit k60_scan_exit(void)
{
	if (wq) {
		cancel_work_sync(&scan_work);
		destroy_workqueue(wq);
	}
	unregister_kprobe(&kp);
	pr_info("k60_scan: unloaded\n");
}

module_init(k60_scan_init);
module_exit(k60_scan_exit);

MODULE_LICENSE("GPL");
