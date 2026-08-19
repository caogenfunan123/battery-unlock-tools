# fcc_unlock v3.1 · Redmi K60 (mondrian) 电池容量解锁

写入 XM_PROP_FG1_FCC = 6500000（对应设计容量 6560mAh）到 ADSP 固件，绕过只读的 fg1_fcc sysfs。

ADSP 固件白名单已确认：adsp.b14 offset 0x24e17c 接受 prop_id=128。

## 原理（v3.1）

GKI 内核（Android 12+）加固导致模块无法使用：
- kallsyms_lookup_name — **不导出**
- filp_open — 在 VFS symbol namespace（需 MODULE_IMPORT_NS）
- kernel_read — **不导出**

因此采用**用户态取址 + insmod 传参**：

```
用户态(root)读 /proc/kallsyms 拿符号地址 → insmod 传参给模块
```

bcdev 定位（双保险）：
1. `power_supply_get_drvdata(psy)` — qti 驱动 probe 设 cfg.drv_data = bcdev，inline 直读
2. `copy_from_kernel_nofault` 安全扫描 psy 前 0x400 字节，检查候选指针 +0x150 处 == battery_prop_map

## 前提

- Root（KernelSU / Magisk）
- 内核 5.10.136-android12-9-00003-g8970630c07cd-ab9368044（GKI 2.0）
- 匹配的 GKI 内核源码树（vermagic 必须一致）

## 编译

```bash
export PATH=/path/to/ndk/toolchains/llvm/prebuilt/linux-x86_64/bin:$PATH
export CROSS_COMPILE=aarch64-linux-android-

git clone <你的 GKI sm8450 内核源码>
cd <内核>
make ARCH=arm64 gki_defconfig
make ARCH=arm64 modules_prepare

cd /path/to/fcc_unlock
make KERNEL_SRC=/path/to/gki_kernel ARCH=arm64
```
输出：fcc_unlock.ko

## 加载

```bash
adb push fcc_unlock.ko /data/local/tmp/
adb push load_fcc.sh /data/local/tmp/
adb shell su -c 'sh /data/local/tmp/load_fcc.sh'
```

load_fcc.sh 从 /proc/kallsyms 取三个地址传给模块：
- chg_write — battery_chg_write 地址
- prop_map — battery_prop_map 地址
- psy_get — power_supply_get_by_name 地址

注意：模块符号（qti_battery_charger）在 kallsyms 里带 [modulename] 后缀，脚本用子串匹配并排除 .cfi_jt。

## 验证

- `cat /sys/class/qcom-battery/fg1_fcc` → **6500000**
- `dmesg | grep fcc` → SUCCESS

## 排错

| 日志 | 含义 | 处理 |
|---|---|---|
| Unknown symbol kallsyms_lookup_name | 旧版用了未导出符号 | 换 v3.1 |
| module uses symbol from namespace VFS... | 用了 VFS namespace 符号 | 换 v3.1 |
| missing addresses | 没传参 | 用 load_fcc.sh |
| battery psy failed | psy_get 地址错 | 核对 kallsyms |
| drv_data ... not bcdev | drv_data 不是 bcdev | 看扫描兜底 |
| no bcdev found | 扫描也失败 | 把 dmesg 发来调 0x150 偏移 |
| write failed ret=... | glink 消息被拒 | 核对 prop_id/owner/opcode |

## 文件

```
fcc_unlock/
├── Makefile
├── fcc_unlock.c    # v3.1
├── load_fcc.sh     # 自动取址加载脚本
└── README.md
```
