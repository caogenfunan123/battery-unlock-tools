# fcc_unlock v3.0 · Redmi K60 (mondrian) 电池容量解锁

写入 XM_PROP_FG1_FCC = 6500000（对应设计容量 6560mAh）到 ADSP 固件，绕过只读的 fg1_fcc sysfs，解除容量锁定。

ADSP 固件白名单已确认：adsp.b14 offset 0x24e17c 接受 prop_id=128。

## 原理（v3.0）

GKI 内核（Android 12+）做了加固，模块无法直接使用：
- `kallsyms_lookup_name` — **不导出**（已从导出符号表移除）
- `filp_open` — 在 VFS symbol namespace 中（`VFS_internal_I_am_really_a_filesystem_and_am_NOT_a_driver`），需要 MODULE_IMPORT_NS
- `kernel_read` — **不导出**

所以 v3.0 采用**用户态取址 + insmod 传参**方案：

```
用户态(root)读 /proc/kallsyms 拿到符号地址
    ↓ insmod 传参
模块零文件依赖，只引用最基础的内核符号
```

模块接收三个参数：
- `chg_write` — battery_chg_write 函数地址（向 ADSP 发 glink 消息）
- `prop_map` — battery_prop_map 符号地址（扫描 psy 结构定位 bcdev）
- `psy_get` — power_supply_get_by_name 函数地址

## 前提

- Root（KernelSU / Magisk）
- 运行内核：5.10.136-android12-9-00003-g8970630c07cd-ab9368044（GKI 2.0）
- 与运行内核匹配的 GKI 内核源码树（vermagic 必须一致，模块才能 insmod）

## 编译

### 1. 交叉编译器（Android NDK）
```bash
export PATH=/path/to/ndk/toolchains/llvm/prebuilt/linux-x86_64/bin:$PATH
export CROSS_COMPILE=aarch64-linux-android-
```

### 2. 内核源码（GKI 树，必须与手机内核版本匹配）
```bash
git clone <你的 GKI sm8450 内核源码仓库>
cd <内核目录>
make ARCH=arm64 gki_defconfig
make ARCH=arm64 modules_prepare
```

### 3. 编译模块
```bash
cd /path/to/fcc_unlock
make KERNEL_SRC=/path/to/gki_kernel ARCH=arm64
```
输出：fcc_unlock.ko

## 加载（load_fcc.sh 自动取址）

把 `fcc_unlock.ko` 和 `load_fcc.sh` 都推到手机：

```bash
adb push fcc_unlock.ko /data/local/tmp/
adb push load_fcc.sh /data/local/tmp/
adb shell su -c 'sh /data/local/tmp/load_fcc.sh'
```

load_fcc.sh 做的事：
```bash
CHG=$(grep " battery_chg_write$" /proc/kallsyms | head -1 | awk '{print $1}')
PMAP=$(grep " battery_prop_map$" /proc/kallsyms | head -1 | awk '{print $1}')
PSYGET=$(grep " power_supply_get_by_name$" /proc/kallsyms | head -1 | awk '{print $1}')
insmod /data/local/tmp/fcc_unlock.ko chg_write=0x$CHG prop_map=0x$PMAP psy_get=0x$PSYGET
```

需要先确认 `kptr_restrict=0`（脚本里已处理）。

## 验证

- `cat /sys/class/qcom-battery/fg1_fcc` → 应显示 **6500000**
- `dmesg | grep fcc` → 模块日志（SUCCESS 即成功）

## 排错

| dmesg 日志 | 含义 | 处理 |
|---|---|---|
| `Unknown symbol kallsyms_lookup_name` | 旧版本用了未导出符号 | 换 v3.0 |
| `module uses symbol from namespace VFS...` | 用了 VFS namespace 符号 | 换 v3.0（不再读文件） |
| `missing addresses` | 没传参 | 用 load_fcc.sh 加载 |
| `power_supply_get_by_name(battery) failed` | psy_get 地址错或驱动未加载 | 核对 kallsyms 地址 |
| `battery_prop_map not found in psy struct` | 0x150 偏移不对 | 把 dmesg 发来调偏移 |
| `write failed ret=...` | glink 消息被固件拒 | 核对 prop_id/owner/opcode |

## 文件

```
fcc_unlock/
├── Makefile        # 编译脚本
├── fcc_unlock.c    # 模块源码（v3.0）
├── load_fcc.sh     # 自动取址加载脚本
└── README.md       # 本文件
```