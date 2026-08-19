// SPDX-License-Identifier: GPL-2.0-only
/*
 * fcc_unlock v3.0 - Redmi K60 (mondrian) battery capacity unlock
 *
 * Addresses are passed via module params (read from /proc/kallsyms
 * in userspace by load_fcc.sh). Module itself references only basic
 * exported kernel symbols - no file I/O, no VFS namespace, no
 * kallsyms_lookup_name (GKI does not export it).
 *
 * insmod fcc_unlock.ko chg_write=0x<addr> prop_map=0x<addr> psy_get=0x<addr>
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/slab.h>

#define PMIC_GLINK_OWNER_XIAOMI_BATTERY_CHG    0x800A
#define PMIC_GLINK_CMD_REQ                     1
#define BC_XM_STATUS_SET                       0x51
#define XM_PROP_FG1_FCC                        128
#define FCC_TARGET_uAh                          6500000

/* module params: symbol addresses from /proc/kallsyms (userspace) */
static unsigned long chg_write = 0;
static unsigned long prop_map = 0;
static unsigned long psy_get = 0;
module_param(chg_write, ulong, 0);
module_param(prop_map, ulong, 0);
module_param(psy_get, ulong, 0);

/* hard-coded offsets (compile-time constant for this kernel build) */
#define BCDEV_PSY_LIST_MAP_OFF 0x150

struct pmic_glink_hdr { u32 owner; u32 type; u32 opcode; } __packed;
struct battery_charger_req_msg {
    struct pmic_glink_hdr hdr;
    int battery_id;
    int property_id;
    int value;
} __packed;

typedef int (*battery_chg_write_t)(void *, struct battery_charger_req_msg *, int);
typedef void *(*psy_get_t)(const char *);

static int __init fcc_unlock_init(void)
{
    battery_chg_write_t write_fn;
    psy_get_t psy_get_fn;
    struct battery_charger_req_msg msg;
    void *psy;
    unsigned long *p;
    void *bcdev = NULL;
    int i, ret;

    pr_info("fcc: v3.0 starting (chg_write=0x%lx prop_map=0x%lx psy_get=0x%lx)\n",
            chg_write, prop_map, psy_get);

    if (!chg_write || !prop_map || !psy_get) {
        pr_err("fcc: missing addresses - use load_fcc.sh to pass params\n");
        return -EINVAL;
    }

    write_fn = (battery_chg_write_t)chg_write;
    psy_get_fn = (psy_get_t)psy_get;

    psy = psy_get_fn("battery");
    if (!psy) {
        pr_err("fcc: power_supply_get_by_name(battery) failed\n");
        return -ENODEV;
    }
    pr_info("fcc: psy at %p\n", psy);

    /* scan psy struct for a pointer equal to battery_prop_map.
     * battery_prop_map lives at bcdev + 0x150 (psy_list[0].map).
     * found at psy+offset i -> bcdev = psy + i - 0x150 */
    p = (unsigned long *)psy;
    for (i = 0; i < 0x200; i += 8) {
        if (p[i/8] == prop_map) {
            bcdev = (void *)((unsigned long)psy + i - BCDEV_PSY_LIST_MAP_OFF);
            pr_info("fcc: prop_map at psy+0x%x, bcdev=0x%lx\n",
                    i, (unsigned long)bcdev);
            break;
        }
    }

    if (!bcdev) {
        pr_err("fcc: battery_prop_map (0x%lx) not found in psy struct\n", prop_map);
        return -ENODEV;
    }

    memset(&msg, 0, sizeof(msg));
    msg.hdr.owner   = PMIC_GLINK_OWNER_XIAOMI_BATTERY_CHG;
    msg.hdr.type    = PMIC_GLINK_CMD_REQ;
    msg.hdr.opcode  = BC_XM_STATUS_SET;
    msg.battery_id  = 0;
    msg.property_id = XM_PROP_FG1_FCC;
    msg.value       = FCC_TARGET_uAh;

    pr_info("fcc: writing fg1_fcc = %d uAh\n", FCC_TARGET_uAh);
    ret = write_fn(bcdev, &msg, sizeof(msg));
    pr_info("fcc: battery_chg_write returned %d\n", ret);

    if (ret == 0)
        pr_info("fcc: SUCCESS - check /sys/class/qcom-battery/fg1_fcc\n");
    else
        pr_warn("fcc: write failed ret=%d\n", ret);

    return 0;
}

static void __exit fcc_unlock_exit(void)
{
    pr_info("fcc: unloaded\n");
}

module_init(fcc_unlock_init);
module_exit(fcc_unlock_exit);
MODULE_LICENSE("GPL v2");
MODULE_DESCRIPTION("FCC unlock for Redmi K60 (params via userspace)");
MODULE_VERSION("3.0");