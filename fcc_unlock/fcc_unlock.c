// SPDX-License-Identifier: GPL-2.0-only
/*
 * fcc_unlock v3.1 - Redmi K60 (mondrian) battery capacity unlock
 *
 * Addresses passed via module params (userspace reads /proc/kallsyms).
 * bcdev located via psy->drv_data (qti driver sets cfg.drv_data=bcdev),
 * with safe scan fallback using copy_from_kernel_nofault.
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/slab.h>
#include <linux/power_supply.h>
#include <linux/uaccess.h>

#define PMIC_GLINK_OWNER_XIAOMI_BATTERY_CHG    0x800A
#define PMIC_GLINK_CMD_REQ                     1
#define BC_XM_STATUS_SET                       0x51
#define XM_PROP_FG1_FCC                        128
#define FCC_TARGET_uAh                          6500000
#define BCDEV_PSY_LIST_MAP_OFF                 0x150

static unsigned long chg_write = 0;
static unsigned long prop_map = 0;
static unsigned long psy_get = 0;
module_param(chg_write, ulong, 0);
module_param(prop_map, ulong, 0);
module_param(psy_get, ulong, 0);

struct pmic_glink_hdr { u32 owner; u32 type; u32 opcode; } __packed;
struct battery_charger_req_msg {
	struct pmic_glink_hdr hdr;
	int battery_id;
	int property_id;
	int value;
} __packed;

typedef int (*battery_chg_write_t)(void *, struct battery_charger_req_msg *, int);
typedef void *(*psy_get_t)(const char *);

static int kread8(void *dst, const void *src)
{
	return copy_from_kernel_nofault(dst, src, 8);
}

static void *scan_bcdev(void *psy, unsigned long prop_map)
{
	unsigned long *p = (unsigned long *)psy;
	int i;

	for (i = 0; i < 0x80; i += 8) {
		unsigned long cand = 0;
		unsigned long val = 0;

		if (kread8(&cand, (void *)&p[i/8]) != 0)
			continue;
		if ((cand >> 40) != 0xffffff)
			continue;
		if (kread8(&val, (void *)(cand + BCDEV_PSY_LIST_MAP_OFF)) != 0)
			continue;
		if (val == prop_map) {
			pr_info("fcc: bcdev via scan at 0x%lx (psy+0x%x)\n", cand, i);
			return (void *)cand;
		}
	}
	return NULL;
}

static int __init fcc_unlock_init(void)
{
	battery_chg_write_t write_fn;
	psy_get_t psy_get_fn;
	struct battery_charger_req_msg msg;
	struct power_supply *psy;
	void *bcdev = NULL;
	int ret;

	pr_info("fcc: v3.1 starting (chg_write=0x%lx prop_map=0x%lx psy_get=0x%lx)\n",
		chg_write, prop_map, psy_get);

	if (!chg_write || !prop_map || !psy_get) {
		pr_err("fcc: missing addresses - use load_fcc.sh\n");
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

	bcdev = power_supply_get_drvdata(psy);
	if (bcdev) {
		unsigned long m = 0;
		if (kread8(&m, (void *)((unsigned long)bcdev + BCDEV_PSY_LIST_MAP_OFF)) == 0 &&
		    m == prop_map) {
			pr_info("fcc: bcdev via drv_data at %p (map@0x150 ok)\n", bcdev);
		} else {
			pr_info("fcc: drv_data %p not bcdev (map mismatch), scanning\n", bcdev);
			bcdev = NULL;
		}
	}

	if (!bcdev)
		bcdev = scan_bcdev((void *)psy, prop_map);

	if (!bcdev) {
		pr_err("fcc: no bcdev found\n");
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
MODULE_DESCRIPTION("FCC unlock for Redmi K60 (params, drv_data bcdev)");
MODULE_VERSION("3.1");