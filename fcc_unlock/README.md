# fcc_unlock - Redmi K60 (mondrian) Battery Capacity Unlock

Write XM_PROP_FG1_FCC = 6500000 to ADSP firmware via glink.

## Build

```bash
export CROSS_COMPILE=aarch64-linux-android-
git clone https://github.com/Kirara-Next/kernel_xiaomi_sm8450.git
cd kernel_xiaomi_sm8450
make ARCH=arm64 sm8450_defconfig
make ARCH=arm64 modules_prepare
cd /path/to/fcc_unlock
make KERNEL_SRC=/path/to/kernel_xiaomi_sm8450 ARCH=arm64
```

## Load

```bash
adb push fcc_unlock.ko /data/local/tmp/
adb shell su -c insmod /data/local/tmp/fcc_unlock.ko
cat /sys/class/qcom-battery/fg1_fcc
dmesg | grep fcc
```

## Files

- Makefile - build script
- fcc_unlock.c - module source
- README.md - this file
