/* k60_vol_write.c - write FG1_VOL_MAX (prop 126) via fake_soh channel (accepted writes) */
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/kprobes.h>
#include <linux/ptrace.h>

#define XM_PROP_FAKE_SOH 93
#define XM_PROP_FG1_VOL_MAX 126
#define REQ_MSG_OPCODE_OFF 8
#define REQ_MSG_PROP_ID_OFF 16
#define REQ_MSG_VALUE_OFF 20
#define REQ_MSG_MIN_LEN 24
#define BC_XM_STATUS_SET 0x51

static unsigned int target_prop = XM_PROP_FG1_VOL_MAX;
module_param(target_prop, uint, 0644);
static unsigned int target_volt = 4480000;
module_param(target_volt, uint, 0644);
static unsigned long hit_count;
module_param(hit_count, ulong, 0644);

static struct kprobe kp;

static int k60_volw_pre(struct kprobe *p, struct pt_regs *regs) {
  u32 *msg = (u32 *)regs->regs[1];
  unsigned long len = regs->regs[2];
  u32 opcode, prop, val;

  if (!msg || len < REQ_MSG_MIN_LEN) return 0;
  opcode = msg[REQ_MSG_OPCODE_OFF / 4];
  if (opcode != BC_XM_STATUS_SET) return 0;
  prop = msg[REQ_MSG_PROP_ID_OFF / 4];
  val = msg[REQ_MSG_VALUE_OFF / 4];
  if (prop == XM_PROP_FAKE_SOH || prop == target_prop) {
    hit_count++;
    pr_info("k60_volw: XM-SET prop=%u val=%u rewrite->prop=%u val=%u\n", prop, val, target_prop, target_volt);
    msg[REQ_MSG_PROP_ID_OFF / 4] = target_prop;
    msg[REQ_MSG_VALUE_OFF / 4] = target_volt;
  }
  return 0;
}

static int __init k60_volw_init(void) {
  kp.symbol_name = "battery_chg_write";
  kp.pre_handler = k60_volw_pre;
  if (register_kprobe(&kp)) {
    pr_err("k60_volw: register_kprobe failed\n");
    return -EINVAL;
  }
  pr_info("k60_volw: registered target_prop=%u target_volt=%u\n", target_prop, target_volt);
  return 0;
}

static void __exit k60_volw_exit(void) {
  unregister_kprobe(&kp);
  pr_info("k60_volw: unregistered hits=%lu\n", hit_count);
}

module_init(k60_volw_init);
module_exit(k60_volw_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Write FG1_VOL_MAX via fake_soh channel (prop126)");