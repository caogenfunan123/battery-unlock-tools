// SPDX-License-Identifier: GPL-2.0-only
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/power_supply.h>
#include <linux/fs.h>
#include <linux/uaccess.h>
#include <linux/slab.h>
#include <linux/vmalloc.h>

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

/* Find kernel symbol address by reading /proc/kallsyms */
static void *find_sym(const char *name)
{
    struct file *f;
    loff_t pos = 0;
    char *buf;
    int ret;
    void *addr = NULL;
    int name_len = strlen(name);

    f = filp_open("/proc/kallsyms", O_RDONLY, 0);
    if (IS_ERR(f)) {
        pr_err("fcc: cannot open /proc/kallsyms\n");
        return NULL;
    }

    buf = vmalloc(65536);
    if (!buf) {
        filp_close(f, NULL);
        return NULL;
    }

    ret = kernel_read(f, buf, 65536, &pos);
    if (ret > 0) {
        char *p = buf;
        char *end = buf + ret;
        while (p < end) {
            char *nl = strchr(p, '\n');
            if (!nl) break;
            *nl = '\0';
            /* Format: "ADDRESS TYPE name" */
            char *type_start = strchr(p, ' ');
            if (type_start) {
                type_start++;
                char *name_start = strchr(type_start, ' ');
                if (name_start) {
                    name_start++;
                    if (strcmp(name_start, name) == 0) {
                        unsigned long val;
                        if (sscanf(p, "%lx", &val) == 1 && val) {
                            addr = (void *)val;
                            break;
                        }
                    }
                }
            }
            p = nl + 1;
        }
    }

    vfree(buf);
    filp_close(f, NULL);
    return addr;
}

static void *find_bcdev(void)
{
    struct power_supply *psy;
    void *(*psy_get)(const char *);
    void *battery_prop_map;
    unsigned long *p;
    int i;

    psy_get = find_sym("power_supply_get_by_name");
    if (!psy_get) { pr_err("fcc: no power_supply_get_by_name\n"); return NULL; }

    psy = psy_get("battery");
    if (!psy) { pr_err("fcc: no battery psy\n"); return NULL; }

    battery_prop_map = find_sym("battery_prop_map");
    if (!battery_prop_map) { pr_err("fcc: no battery_prop_map\n"); return NULL; }

    p = (unsigned long *)psy;
    for (i = 0; i < 0x200; i += 8) {
        if (p[i/8] == (unsigned long)battery_prop_map) {
            void *bcdev = (void *)((unsigned long)psy + i - 0x150);
            pr_info("fcc: found bcdev at %p (offset 0x%x)\n", bcdev, i);
            return bcdev;
        }
    }

    pr_err("fcc: battery_prop_map not found in psy struct\n");
    return NULL;
}

static int __init fcc_unlock_init(void)
{
    battery_chg_write_t battery_chg_write_fn;
    void *bcdev;
    struct battery_charger_req_msg msg;
    int ret;

    pr_info("fcc: starting\n");

    bcdev = find_bcdev();
    if (!bcdev) { pr_err("fcc: no bcdev\n"); return -ENODEV; }

    battery_chg_write_fn = find_sym("battery_chg_write");
    if (!battery_chg_write_fn) { pr_err("fcc: no battery_chg_write\n"); return -ENODEV; }

    memset(&msg, 0, sizeof(msg));
    msg.hdr.owner    = PMIC_GLINK_OWNER_XIAOMI_BATTERY_CHG;
    msg.hdr.type     = PMIC_GLINK_CMD_REQ;
    msg.hdr.opcode   = BC_XM_STATUS_SET;
    msg.battery_id   = 0;
    msg.property_id  = XM_PROP_FG1_FCC;
    msg.value        = FCC_TARGET_uAh;

    pr_info("fcc: writing fg1_fcc = %d\n", FCC_TARGET_uAh);
    ret = battery_chg_write_fn(bcdev, &msg, sizeof(msg));
    pr_info("fcc: battery_chg_write returned %d\n", ret);

    if (ret == 0) pr_info("fcc: SUCCESS\n");
    else pr_warn("fcc: write failed ret=%d\n", ret);

    return 0;
}

static void __exit fcc_unlock_exit(void) { pr_info("fcc: unloaded\n"); }
module_init(fcc_unlock_init);
module_exit(fcc_unlock_exit);
MODULE_LICENSE("GPL v2");
MODULE_DESCRIPTION("FCC unlock for Redmi K60");
MODULE_VERSION("2.0");