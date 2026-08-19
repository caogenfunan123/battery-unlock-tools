# fcc_unlock · Redmi K60 (mondrian) 电池容量解锁

写入 XM_PROP_FG1_FCC = 6500000 到 ADSP 固件（绕过只读的 fg1_fcc sysfs）。

ADSP 白名单确认：adsp.b14 offset 0x24e17c 接受 prop_id=128。

## 前提

- Root（KernelSU / Magisk）
- 运行内核：5.10.136-android12-9（GKI 2.0）
- 与运行内核匹配的 GKI 内核源码树

## 编译

### 1. 交叉编译器（Android NDK）
```bash
export PATH=/path/to/ndk/toolchains/llvm/prebuilt/linux-x86_64/bin:$PATH
export CROSS_COMPILE=aarch64-linux-android-
```

### 2. 内核源码（GKI 树，必须与手机内核版本匹配）
Redmi K60 (mondrian) 原厂 MIUI 内核 5.10.136-android12-9：
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

## 加载
```bash
adb push fcc_unlock.ko /data/local/tmp/
adb shell su -c 'dmesg -c > /dev/null 2>&1; insmod /data/local/tmp/fcc_unlock.ko; echo exit=$?; dmesg | tail -10'
cat /sys/class/qcom-battery/fg1_fcc
```

## 验证
- cat /sys/class/qcom-battery/fg1_fcc → 应显示 6500000
- dmesg | grep fcc → 模块日志

## 重要说明
- GKI 内核**不导出** kallsyms_lookup_name（Android 12+ 加固移除）。
  模块改用 filp_open+kernel_read 读 /proc/kallsyms 解析地址，KASLR 免疫。
- bcdev 扫描用 0x150 偏移（psy_list[0].map 相对 bcdev）。
  如果 insmod 报 "no bcdev"，把 dmesg 里的扫描偏移发来调整。
- 需要导出的符号：filp_open、kernel_read、power_supply_get_by_name（GKI 均有导出）。

## 文件
- Makefile — 编译脚本
- fcc_unlock.c — 模块源码
- README.md — 本文件