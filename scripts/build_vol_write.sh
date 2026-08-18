#!/bin/bash
# build_vol_write.sh - one-click compile for k60_vol_write.ko (run on PC)
set -e

echo '[1/4] check env...'
command -v adb >/dev/null 2>&1 || { echo 'ERR: no adb'; exit 1; }
adb devices | grep -q 'device$' || { echo 'ERR: phone not connected (enable USB debugging)'; exit 1; }
[ -d /tmp/opencode/gki136 ] || { echo 'ERR: no /tmp/opencode/gki136 kernel tree'; exit 1; }

echo '[2/4] pull source from phone...'
rm -rf /tmp/k60build && mkdir -p /tmp/k60build
adb pull /data/adb/modules/k60_battery_unlock/kernel/k60_vol_write.c /tmp/k60build/ >/dev/null
cat > /tmp/k60build/Kbuild <<'EOF'
obj-m := k60_vol_write.o

KDIR ?= /tmp/opencode/gki136
TOOLCHAIN ?= /tmp/opencode/ddk/clang-r416183b

CC := $(TOOLCHAIN)/bin/clang
LD := $(TOOLCHAIN)/bin/ld.lld
NM := $(TOOLCHAIN)/bin/llvm-nm
OBJCOPY := $(TOOLCHAIN)/bin/llvm-objcopy
OBJDUMP := $(TOOLCHAIN)/bin/llvm-objdump
READELF := $(TOOLCHAIN)/bin/llvm-readelf
AR := $(TOOLCHAIN)/bin/llvm-ar

all:
	$(MAKE) ARCH=arm64 CC=$(CC) LD=$(LD) NM=$(NM) OBJCOPY=$(OBJCOPY) OBJDUMP=$(OBJDUMP) READELF=$(READELF) AR=$(AR) -C $(KDIR) M=$(CURDIR) modules

clean:
	$(MAKE) ARCH=arm64 -C $(KDIR) M=$(CURDIR) clean
EOF

echo '[3/4] compiling...'
cd /tmp/k60build && make -C /tmp/opencode/gki136 M=/tmp/k60build modules

echo '[4/4] push back to phone...'
ls -la /tmp/k60build/k60_vol_write.ko
adb push /tmp/k60build/k60_vol_write.ko /data/adb/modules/k60_battery_unlock/kernel/
echo ''
echo '=============================================='
echo 'DONE! k60_vol_write.ko pushed. On phone run:'
echo '  insmod k60_vol_write.ko target_volt=4480000'
echo '  echo 100 > /sys/class/qcom-battery/fake_soh   (trigger rewrite)'
echo '=============================================='