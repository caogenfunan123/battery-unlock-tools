// SPDX-License-Identifier: GPL-2.0-only
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/power_supply.h>
#include <linux/kallsyms.h>
#include <linux/device.h>
#include <linux/slab.h>

#define PMIC_GLINK_OWNER_XIAOMI_BATTERY_CHG    0x800A
#define PMIC_GLINK_CMD_REQ                     1
#define BC_XM_STATUS_SET                       0x51
#define XM_PROP_FG1_FCC                        128
#define FCC_TARGET_uAh                          6500000

struct pmic_glink_hdr { u32 owner; u32 type; u32 opcode; } __packed;
struct battery_charger_req_msg {
    struct pmic_glink_hdr hdr;
    int battery_id;
    int property_id;
    int value;
} __packed;

typedef int (*battery_chg_write_t)(void *, struct battery_charger_req_msg *, int);
static battery_chg_write_t battery_chg_write_fn;

static void *resolve_sym(const char *name)
{
    unsigned long (*kl)(const char *);
    kl = (void *)kallsyms_lookup_name("kallsyms_lookup_name");
    if (!kl) return NULL;
    return (void *)kl(name);
}

static void *find_bcdev(void)
{
    struct power_supply *psy;
    void *bcdev = NULL;
    void *(*psy_get)(const char *);
    void *battery_prop_map;
    unsigned long *p;
    int i;

    psy_get = resolve_sym("power_supply_get_by_name");
    if (!psy_get) return NULL;
    psy = psy_get("battery");
    if (!psy) { pr_err("fcc: no battery
"); return NULL; }

    battery_prop_map = resolve_sym("battery_prop_map");
    if (battery_prop_map) {
        p = (unsigned long *)psy;
        for (i = 0; i < 0x200; i += 8) {
            if (p[i/8] == (unsigned long)battery_prop_map) {
                bcdev = (void *)((unsigned long)psy + i - 0x150);
                break;
            }
        }
    }
    return bcdev;
}

static int __init fcc_unlock_init(void)
{
    void *bcdev;
    struct battery_charger_req_msg msg;
    int ret;

    pr_info("fcc: starting
");
    battery_chg_write_fn = resolve_sym("battery_chg_write");
    if (!battery_chg_write_fn) { pr_err("fcc: no battery_chg_write
"); return -ENODEV; }

    bcdev = find_bcdev();
    if (!bcdev) { pr_err("fcc: no bcdev
"); return -ENODEV; }
    pr_info("fcc: bcdev at %p
", bcdev);

    memset(&msg, 0, sizeof(msg));
    msg.hdr.owner = PMIC_GLINK_OWNER_XIAOMI_BATTERY_CHG;
    msg.hdr.type = PMIC_GLINK_CMD_REQ;
    msg.hdr.opcode = BC_XM_STATUS_SET;
    msg.battery_id = 0;
    msg.property_id = XM_PROP_FG1_FCC;
    msg.value = FCC_TARGET_uAh;

    pr_info("fcc: writing fg1_fcc = %d
", FCC_TARGET_uAh);
    ret = battery_chg_write_fn(bcdev, &msg, sizeof(msg));
    pr_info("fcc: battery_chg_write returned %d
", ret);
    if (ret == 0) pr_info("fcc: SUCCESS
");
    else pr_warn("fcc: write failed ret=%d
", ret);
    return 0;
}

static void __exit fcc_unlock_exit(void) { pr_info("fcc: unloaded
"); }
module_init(fcc_unlock_init);
module_exit(fcc_unlock_exit);
MODULE_LICENSE("GPL v2");
MODULE_DESCRIPTION("FCC unlock for Redmi K60");
MODULE_VERSION("1.0");
